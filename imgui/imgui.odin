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
	foreign import lib "wasm/c_imgui.o"
	@(require) foreign import "wasm/imgui.o"
	@(require) foreign import "wasm/imgui_demo.o"
	@(require) foreign import "wasm/imgui_draw.o"
	@(require) foreign import "wasm/imgui_tables.o"
	@(require) foreign import "wasm/imgui_widgets.o"
}

CHECKVERSION :: proc() {
	DebugCheckVersionAndDataLayout(VERSION, size_of(IO), size_of(Style), size_of(Vec2), size_of(Vec4), size_of(DrawVert), size_of(DrawIdx))
}

////////////////////////////////////////////////////////////
// DEFINES
////////////////////////////////////////////////////////////

VERSION                      :: "1.91.7"
VERSION_NUM                  :: 19170
PAYLOAD_TYPE_COLOR_3F        :: "_COL3F" // float[3]: Standard type for colors, without alpha. User code may use this type.
PAYLOAD_TYPE_COLOR_4F        :: "_COL4F" // float[4]: Standard type for colors. User code may use this type.
UNICODE_CODEPOINT_INVALID    :: 0xFFFD   // Invalid Unicode code point (standard value).
UNICODE_CODEPOINT_MAX        :: 0xFFFF   // Maximum Unicode code point supported by this build.
DRAWLIST_TEX_LINES_WIDTH_MAX :: 63

////////////////////////////////////////////////////////////
// ENUMS
////////////////////////////////////////////////////////////

// Flags for ImGui::Begin()
// (Those are per-window flags. There are shared flags in ImGuiIO: io.ConfigWindowsResizeFromEdges and io.ConfigWindowsMoveFromTitleBarOnly)
WindowFlags :: bit_set[WindowFlag; c.int]
WindowFlag :: enum c.int {
	NoTitleBar                = 0,  // Disable title-bar
	NoResize                  = 1,  // Disable user resizing with the lower-right grip
	NoMove                    = 2,  // Disable user moving the window
	NoScrollbar               = 3,  // Disable scrollbars (window can still scroll with mouse or programmatically)
	NoScrollWithMouse         = 4,  // Disable user vertically scrolling with mouse wheel. On child window, mouse wheel will be forwarded to the parent unless NoScrollbar is also set.
	NoCollapse                = 5,  // Disable user collapsing window by double-clicking on it. Also referred to as Window Menu Button (e.g. within a docking node).
	AlwaysAutoResize          = 6,  // Resize every window to its content every frame
	NoBackground              = 7,  // Disable drawing background color (WindowBg, etc.) and outside border. Similar as using SetNextWindowBgAlpha(0.0f).
	NoSavedSettings           = 8,  // Never load/save settings in .ini file
	NoMouseInputs             = 9,  // Disable catching mouse, hovering test with pass through.
	MenuBar                   = 10, // Has a menu-bar
	HorizontalScrollbar       = 11, // Allow horizontal scrollbar to appear (off by default). You may use SetNextWindowContentSize(ImVec2(width,0.0f)); prior to calling Begin() to specify width. Read code in imgui_demo in the "Horizontal Scrolling" section.
	NoFocusOnAppearing        = 12, // Disable taking focus when transitioning from hidden to visible state
	NoBringToFrontOnFocus     = 13, // Disable bringing window to front when taking focus (e.g. clicking on it or programmatically giving it focus)
	AlwaysVerticalScrollbar   = 14, // Always show vertical scrollbar (even if ContentSize.y < Size.y)
	AlwaysHorizontalScrollbar = 15, // Always show horizontal scrollbar (even if ContentSize.x < Size.x)
	NoNavInputs               = 16, // No keyboard/gamepad navigation within the window
	NoNavFocus                = 17, // No focusing toward this window with keyboard/gamepad navigation (e.g. skipped by CTRL+TAB)
	UnsavedDocument           = 18, // Display a dot next to the title. When used in a tab/docking context, tab is selected when clicking the X + closure is not assumed (will wait for user to stop submitting the tab). Otherwise closure is assumed when pressing the X, so if you keep submitting the tab may reappear at end of tab bar.
	NoDocking                 = 19, // Disable docking of this window
	// [Internal]
	ChildWindow  = 24, // Don't use! For internal use by BeginChild()
	Tooltip      = 25, // Don't use! For internal use by BeginTooltip()
	Popup        = 26, // Don't use! For internal use by BeginPopup()
	Modal        = 27, // Don't use! For internal use by BeginPopupModal()
	ChildMenu    = 28, // Don't use! For internal use by BeginMenu()
	DockNodeHost = 29, // Don't use! For internal use by Begin()/NewFrame()
}

WindowFlags_NoNav        :: WindowFlags{.NoNavInputs,.NoNavFocus}
WindowFlags_NoDecoration :: WindowFlags{.NoTitleBar,.NoResize,.NoScrollbar,.NoCollapse}
WindowFlags_NoInputs     :: WindowFlags{.NoMouseInputs,.NoNavInputs,.NoNavFocus}

// Flags for ImGui::BeginChild()
// (Legacy: bit 0 must always correspond to ImGuiChildFlags_Borders to be backward compatible with old API using 'bool border = false'.
// About using AutoResizeX/AutoResizeY flags:
// - May be combined with SetNextWindowSizeConstraints() to set a min/max size for each axis (see "Demo->Child->Auto-resize with Constraints").
// - Size measurement for a given axis is only performed when the child window is within visible boundaries, or is just appearing.
//   - This allows BeginChild() to return false when not within boundaries (e.g. when scrolling), which is more optimal. BUT it won't update its auto-size while clipped.
//     While not perfect, it is a better default behavior as the always-on performance gain is more valuable than the occasional "resizing after becoming visible again" glitch.
//   - You may also use ImGuiChildFlags_AlwaysAutoResize to force an update even when child window is not in view.
//     HOWEVER PLEASE UNDERSTAND THAT DOING SO WILL PREVENT BeginChild() FROM EVER RETURNING FALSE, disabling benefits of coarse clipping.
ChildFlags :: bit_set[ChildFlag; c.int]
ChildFlag :: enum c.int {
	Borders                = 0, // Show an outer border and enable WindowPadding. (IMPORTANT: this is always == 1 == true for legacy reason)
	AlwaysUseWindowPadding = 1, // Pad with style.WindowPadding even if no border are drawn (no padding by default for non-bordered child windows because it makes more sense)
	ResizeX                = 2, // Allow resize from right border (layout direction). Enable .ini saving (unless ImGuiWindowFlags_NoSavedSettings passed to window flags)
	ResizeY                = 3, // Allow resize from bottom border (layout direction). "
	AutoResizeX            = 4, // Enable auto-resizing width. Read "IMPORTANT: Size measurement" details above.
	AutoResizeY            = 5, // Enable auto-resizing height. Read "IMPORTANT: Size measurement" details above.
	AlwaysAutoResize       = 6, // Combined with AutoResizeX/AutoResizeY. Always measure size even when child is hidden, always return true, always disable clipping optimization! NOT RECOMMENDED.
	FrameStyle             = 7, // Style the child window like a framed item: use FrameBg, FrameRounding, FrameBorderSize, FramePadding instead of ChildBg, ChildRounding, ChildBorderSize, WindowPadding.
	NavFlattened           = 8, // [BETA] Share focus scope, allow keyboard/gamepad navigation to cross over parent border to this child or between sibling child windows.
}


// Flags for ImGui::PushItemFlag()
// (Those are shared by all items)
ItemFlags :: bit_set[ItemFlag; c.int]
ItemFlag :: enum c.int {
	NoTabStop         = 0, // false    // Disable keyboard tabbing. This is a "lighter" version of ImGuiItemFlags_NoNav.
	NoNav             = 1, // false    // Disable any form of focusing (keyboard/gamepad directional navigation and SetKeyboardFocusHere() calls).
	NoNavDefaultFocus = 2, // false    // Disable item being a candidate for default focus (e.g. used by title bar items).
	ButtonRepeat      = 3, // false    // Any button-like behavior will have repeat mode enabled (based on io.KeyRepeatDelay and io.KeyRepeatRate values). Note that you can also call IsItemActive() after any button to tell if it is being held.
	AutoClosePopups   = 4, // true     // MenuItem()/Selectable() automatically close their parent popup window.
	AllowDuplicateId  = 5, // false    // Allow submitting an item with the same identifier as an item already submitted this frame without triggering a warning tooltip if io.ConfigDebugHighlightIdConflicts is set.
}


// Flags for ImGui::InputText()
// (Those are per-item flags. There are shared flags in ImGuiIO: io.ConfigInputTextCursorBlink and io.ConfigInputTextEnterKeepActive)
InputTextFlags :: bit_set[InputTextFlag; c.int]
InputTextFlag :: enum c.int {
	CharsDecimal     = 0, // Allow 0123456789.+-*/
	CharsHexadecimal = 1, // Allow 0123456789ABCDEFabcdef
	CharsScientific  = 2, // Allow 0123456789.+-*/eE (Scientific notation input)
	CharsUppercase   = 3, // Turn a..z into A..Z
	CharsNoBlank     = 4, // Filter out spaces, tabs
	// Inputs
	AllowTabInput       = 5, // Pressing TAB input a '\t' character into the text field
	EnterReturnsTrue    = 6, // Return 'true' when Enter is pressed (as opposed to every time the value was modified). Consider using IsItemDeactivatedAfterEdit() instead!
	EscapeClearsAll     = 7, // Escape key clears content if not empty, and deactivate otherwise (contrast to default behavior of Escape to revert)
	CtrlEnterForNewLine = 8, // In multi-line mode, validate with Enter, add new line with Ctrl+Enter (default is opposite: validate with Ctrl+Enter, add line with Enter).
	// Other options
	ReadOnly           = 9,  // Read-only mode
	Password           = 10, // Password mode, display all characters as '*', disable copy
	AlwaysOverwrite    = 11, // Overwrite mode
	AutoSelectAll      = 12, // Select entire text when first taking mouse focus
	ParseEmptyRefVal   = 13, // InputFloat(), InputInt(), InputScalar() etc. only: parse empty string as zero value.
	DisplayEmptyRefVal = 14, // InputFloat(), InputInt(), InputScalar() etc. only: when value is zero, do not display it. Generally used with ImGuiInputTextFlags_ParseEmptyRefVal.
	NoHorizontalScroll = 15, // Disable following the cursor horizontally
	NoUndoRedo         = 16, // Disable undo/redo. Note that input text owns the text data while active, if you want to provide your own undo/redo stack you need e.g. to call ClearActiveID().
	// Elide display / Alignment
	ElideLeft = 17, // When text doesn't fit, elide left side to ensure right side stays visible. Useful for path/filenames. Single-line only!
	// Callback features
	CallbackCompletion = 18, // Callback on pressing TAB (for completion handling)
	CallbackHistory    = 19, // Callback on pressing Up/Down arrows (for history handling)
	CallbackAlways     = 20, // Callback on each iteration. User code may query cursor position, modify text buffer.
	CallbackCharFilter = 21, // Callback on character inputs to replace or discard them. Modify 'EventChar' to replace or discard, or return 1 in callback to discard.
	CallbackResize     = 22, // Callback on buffer capacity changes request (beyond 'buf_size' parameter value), allowing the string to grow. Notify when the string wants to be resized (for string types which hold a cache of their Size). You will be provided a new BufSize in the callback and NEED to honor it. (see misc/cpp/imgui_stdlib.h for an example of using this)
	CallbackEdit       = 23, // Callback on any edit. Note that InputText() already returns true on edit + you can always use IsItemEdited(). The callback is useful to manipulate the underlying buffer while focus is active.
}


// Flags for ImGui::TreeNodeEx(), ImGui::CollapsingHeader*()
TreeNodeFlags :: bit_set[TreeNodeFlag; c.int]
TreeNodeFlag :: enum c.int {
	Selected            = 0,  // Draw as selected
	Framed              = 1,  // Draw frame with background (e.g. for CollapsingHeader)
	AllowOverlap        = 2,  // Hit testing to allow subsequent widgets to overlap this one
	NoTreePushOnOpen    = 3,  // Don't do a TreePush() when open (e.g. for CollapsingHeader) = no extra indent nor pushing on ID stack
	NoAutoOpenOnLog     = 4,  // Don't automatically and temporarily open node when Logging is active (by default logging will automatically open tree nodes)
	DefaultOpen         = 5,  // Default node to be open
	OpenOnDoubleClick   = 6,  // Open on double-click instead of simple click (default for multi-select unless any _OpenOnXXX behavior is set explicitly). Both behaviors may be combined.
	OpenOnArrow         = 7,  // Open when clicking on the arrow part (default for multi-select unless any _OpenOnXXX behavior is set explicitly). Both behaviors may be combined.
	Leaf                = 8,  // No collapsing, no arrow (use as a convenience for leaf nodes).
	Bullet              = 9,  // Display a bullet instead of arrow. IMPORTANT: node can still be marked open/close if you don't set the _Leaf flag!
	FramePadding        = 10, // Use FramePadding (even for an unframed text node) to vertically align text baseline to regular widget height. Equivalent to calling AlignTextToFramePadding() before the node.
	SpanAvailWidth      = 11, // Extend hit box to the right-most edge, even if not framed. This is not the default in order to allow adding other items on the same line without using AllowOverlap mode.
	SpanFullWidth       = 12, // Extend hit box to the left-most and right-most edges (cover the indent area).
	SpanLabelWidth      = 13, // Narrow hit box + narrow hovering highlight, will only cover the label text.
	SpanAllColumns      = 14, // Frame will span all columns of its container table (label will still fit in current column)
	LabelSpanAllColumns = 15, // Label will span all columns of its container table
	//ImGuiTreeNodeFlags_NoScrollOnOpen     = 1 << 16,  // FIXME: TODO: Disable automatic scroll on TreePop() if node got just open and contents is not visible
	NavLeftJumpsBackHere = 17, // (WIP) Nav: left direction may move to this TreeNode() from any of its child (items submitted between TreeNode and TreePop)
}

TreeNodeFlags_CollapsingHeader :: TreeNodeFlags{.Framed,.NoTreePushOnOpen,.NoAutoOpenOnLog}

// Flags for OpenPopup*(), BeginPopupContext*(), IsPopupOpen() functions.
// - To be backward compatible with older API which took an 'int mouse_button = 1' argument instead of 'ImGuiPopupFlags flags',
//   we need to treat small flags values as a mouse button index, so we encode the mouse button in the first few bits of the flags.
//   It is therefore guaranteed to be legal to pass a mouse button index in ImGuiPopupFlags.
// - For the same reason, we exceptionally default the ImGuiPopupFlags argument of BeginPopupContextXXX functions to 1 instead of 0.
//   IMPORTANT: because the default parameter is 1 (==ImGuiPopupFlags_MouseButtonRight), if you rely on the default parameter
//   and want to use another flag, you need to pass in the ImGuiPopupFlags_MouseButtonRight flag explicitly.
// - Multiple buttons currently cannot be combined/or-ed in those functions (we could allow it later).
PopupFlags :: distinct c.int
PopupFlags_None                :: PopupFlags(0)
PopupFlags_MouseButtonLeft     :: PopupFlags(0)    // For BeginPopupContext*(): open on Left Mouse release. Guaranteed to always be == 0 (same as ImGuiMouseButton_Left)
PopupFlags_MouseButtonRight    :: PopupFlags(1)    // For BeginPopupContext*(): open on Right Mouse release. Guaranteed to always be == 1 (same as ImGuiMouseButton_Right)
PopupFlags_MouseButtonMiddle   :: PopupFlags(2)    // For BeginPopupContext*(): open on Middle Mouse release. Guaranteed to always be == 2 (same as ImGuiMouseButton_Middle)
PopupFlags_MouseButtonMask_    :: PopupFlags(0x1F)
PopupFlags_MouseButtonDefault_ :: PopupFlags(1)
PopupFlags_NoReopen            :: PopupFlags(1<<5) // For OpenPopup*(), BeginPopupContext*(): don't reopen same popup if already open (won't reposition, won't reinitialize navigation)
//ImGuiPopupFlags_NoReopenAlwaysNavInit = 1 << 6,   // For OpenPopup*(), BeginPopupContext*(): focus and initialize navigation even when not reopening.
PopupFlags_NoOpenOverExistingPopup :: PopupFlags(1<<7)                                             // For OpenPopup*(), BeginPopupContext*(): don't open if there's already a popup at the same level of the popup stack
PopupFlags_NoOpenOverItems         :: PopupFlags(1<<8)                                             // For BeginPopupContextWindow(): don't return true when hovering items, only when hovering empty space
PopupFlags_AnyPopupId              :: PopupFlags(1<<10)                                            // For IsPopupOpen(): ignore the ImGuiID parameter and test for any popup.
PopupFlags_AnyPopupLevel           :: PopupFlags(1<<11)                                            // For IsPopupOpen(): search/test at any level of the popup stack (default test in the current level)
PopupFlags_AnyPopup                :: PopupFlags(PopupFlags_AnyPopupId | PopupFlags_AnyPopupLevel)

// Flags for ImGui::Selectable()
SelectableFlags :: bit_set[SelectableFlag; c.int]
SelectableFlag :: enum c.int {
	NoAutoClosePopups = 0, // Clicking this doesn't close parent popup window (overrides ImGuiItemFlags_AutoClosePopups)
	SpanAllColumns    = 1, // Frame will span all columns of its container table (text will still fit in current column)
	AllowDoubleClick  = 2, // Generate press events on double clicks too
	Disabled          = 3, // Cannot be selected, display grayed out text
	AllowOverlap      = 4, // (WIP) Hit testing to allow subsequent widgets to overlap this one
	Highlight         = 5, // Make the item be displayed as if it is hovered
}


// Flags for ImGui::BeginCombo()
ComboFlags :: bit_set[ComboFlag; c.int]
ComboFlag :: enum c.int {
	PopupAlignLeft  = 0, // Align the popup toward the left by default
	HeightSmall     = 1, // Max ~4 items visible. Tip: If you want your combo popup to be a specific size you can use SetNextWindowSizeConstraints() prior to calling BeginCombo()
	HeightRegular   = 2, // Max ~8 items visible (default)
	HeightLarge     = 3, // Max ~20 items visible
	HeightLargest   = 4, // As many fitting items as possible
	NoArrowButton   = 5, // Display on the preview box without the square arrow button
	NoPreview       = 6, // Display only a square arrow button
	WidthFitPreview = 7, // Width dynamically calculated from preview contents
}

ComboFlags_HeightMask_ :: ComboFlags{.HeightSmall,.HeightRegular,.HeightLarge,.HeightLargest}

// Flags for ImGui::BeginTabBar()
TabBarFlags :: bit_set[TabBarFlag; c.int]
TabBarFlag :: enum c.int {
	Reorderable                  = 0, // Allow manually dragging tabs to re-order them + New tabs are appended at the end of list
	AutoSelectNewTabs            = 1, // Automatically select new tabs when they appear
	TabListPopupButton           = 2, // Disable buttons to open the tab list popup
	NoCloseWithMiddleMouseButton = 3, // Disable behavior of closing tabs (that are submitted with p_open != NULL) with middle mouse button. You may handle this behavior manually on user's side with if (IsItemHovered() && IsMouseClicked(2)) *p_open = false.
	NoTabListScrollingButtons    = 4, // Disable scrolling buttons (apply when fitting policy is ImGuiTabBarFlags_FittingPolicyScroll)
	NoTooltip                    = 5, // Disable tooltips when hovering a tab
	DrawSelectedOverline         = 6, // Draw selected overline markers over selected tab
	FittingPolicyResizeDown      = 7, // Resize tabs when they don't fit
	FittingPolicyScroll          = 8, // Add scroll buttons when tabs don't fit
}

TabBarFlags_FittingPolicyMask_    :: TabBarFlags{.FittingPolicyResizeDown,.FittingPolicyScroll}
TabBarFlags_FittingPolicyDefault_ :: TabBarFlags{.FittingPolicyResizeDown}

// Flags for ImGui::BeginTabItem()
TabItemFlags :: bit_set[TabItemFlag; c.int]
TabItemFlag :: enum c.int {
	UnsavedDocument              = 0, // Display a dot next to the title + set ImGuiTabItemFlags_NoAssumedClosure.
	SetSelected                  = 1, // Trigger flag to programmatically make the tab selected when calling BeginTabItem()
	NoCloseWithMiddleMouseButton = 2, // Disable behavior of closing tabs (that are submitted with p_open != NULL) with middle mouse button. You may handle this behavior manually on user's side with if (IsItemHovered() && IsMouseClicked(2)) *p_open = false.
	NoPushId                     = 3, // Don't call PushID()/PopID() on BeginTabItem()/EndTabItem()
	NoTooltip                    = 4, // Disable tooltip for the given tab
	NoReorder                    = 5, // Disable reordering this tab or having another tab cross over this tab
	Leading                      = 6, // Enforce the tab position to the left of the tab bar (after the tab list popup button)
	Trailing                     = 7, // Enforce the tab position to the right of the tab bar (before the scrolling buttons)
	NoAssumedClosure             = 8, // Tab is selected when trying to close + closure is not immediately assumed (will wait for user to stop submitting the tab). Otherwise closure is assumed when pressing the X, so if you keep submitting the tab may reappear at end of tab bar.
}


// Flags for ImGui::IsWindowFocused()
FocusedFlags :: bit_set[FocusedFlag; c.int]
FocusedFlag :: enum c.int {
	ChildWindows     = 0, // Return true if any children of the window is focused
	RootWindow       = 1, // Test from root window (top most parent of the current hierarchy)
	AnyWindow        = 2, // Return true if any window is focused. Important: If you are trying to tell how to dispatch your low-level inputs, do NOT use this. Use 'io.WantCaptureMouse' instead! Please read the FAQ!
	NoPopupHierarchy = 3, // Do not consider popup hierarchy (do not treat popup emitter as parent of popup) (when used with _ChildWindows or _RootWindow)
	DockHierarchy    = 4, // Consider docking hierarchy (treat dockspace host as parent of docked window) (when used with _ChildWindows or _RootWindow)
}

FocusedFlags_RootAndChildWindows :: FocusedFlags{.RootWindow,.ChildWindows}

// Flags for ImGui::IsItemHovered(), ImGui::IsWindowHovered()
// Note: if you are trying to check whether your mouse should be dispatched to Dear ImGui or to your app, you should use 'io.WantCaptureMouse' instead! Please read the FAQ!
// Note: windows with the ImGuiWindowFlags_NoInputs flag are ignored by IsWindowHovered() calls.
HoveredFlags :: distinct c.int
HoveredFlags_None                    :: HoveredFlags(0)    // Return true if directly over the item/window, not obstructed by another window, not obstructed by an active popup or modal blocking inputs under them.
HoveredFlags_ChildWindows            :: HoveredFlags(1<<0) // IsWindowHovered() only: Return true if any children of the window is hovered
HoveredFlags_RootWindow              :: HoveredFlags(1<<1) // IsWindowHovered() only: Test from root window (top most parent of the current hierarchy)
HoveredFlags_AnyWindow               :: HoveredFlags(1<<2) // IsWindowHovered() only: Return true if any window is hovered
HoveredFlags_NoPopupHierarchy        :: HoveredFlags(1<<3) // IsWindowHovered() only: Do not consider popup hierarchy (do not treat popup emitter as parent of popup) (when used with _ChildWindows or _RootWindow)
HoveredFlags_DockHierarchy           :: HoveredFlags(1<<4) // IsWindowHovered() only: Consider docking hierarchy (treat dockspace host as parent of docked window) (when used with _ChildWindows or _RootWindow)
HoveredFlags_AllowWhenBlockedByPopup :: HoveredFlags(1<<5) // Return true even if a popup window is normally blocking access to this item/window
//ImGuiHoveredFlags_AllowWhenBlockedByModal     = 1 << 6,   // Return true even if a modal popup window is normally blocking access to this item/window. FIXME-TODO: Unavailable yet.
HoveredFlags_AllowWhenBlockedByActiveItem :: HoveredFlags(1<<7)                                                                                                                // Return true even if an active item is blocking access to this item/window. Useful for Drag and Drop patterns.
HoveredFlags_AllowWhenOverlappedByItem    :: HoveredFlags(1<<8)                                                                                                                // IsItemHovered() only: Return true even if the item uses AllowOverlap mode and is overlapped by another hoverable item.
HoveredFlags_AllowWhenOverlappedByWindow  :: HoveredFlags(1<<9)                                                                                                                // IsItemHovered() only: Return true even if the position is obstructed or overlapped by another window.
HoveredFlags_AllowWhenDisabled            :: HoveredFlags(1<<10)                                                                                                               // IsItemHovered() only: Return true even if the item is disabled
HoveredFlags_NoNavOverride                :: HoveredFlags(1<<11)                                                                                                               // IsItemHovered() only: Disable using keyboard/gamepad navigation state when active, always query mouse
HoveredFlags_AllowWhenOverlapped          :: HoveredFlags(HoveredFlags_AllowWhenOverlappedByItem | HoveredFlags_AllowWhenOverlappedByWindow)
HoveredFlags_RectOnly                     :: HoveredFlags(HoveredFlags_AllowWhenBlockedByPopup | HoveredFlags_AllowWhenBlockedByActiveItem | HoveredFlags_AllowWhenOverlapped)
HoveredFlags_RootAndChildWindows          :: HoveredFlags(HoveredFlags_RootWindow | HoveredFlags_ChildWindows)
// Tooltips mode
// - typically used in IsItemHovered() + SetTooltip() sequence.
// - this is a shortcut to pull flags from 'style.HoverFlagsForTooltipMouse' or 'style.HoverFlagsForTooltipNav' where you can reconfigure desired behavior.
//   e.g. 'TooltipHoveredFlagsForMouse' defaults to 'ImGuiHoveredFlags_Stationary | ImGuiHoveredFlags_DelayShort'.
// - for frequently actioned or hovered items providing a tooltip, you want may to use ImGuiHoveredFlags_ForTooltip (stationary + delay) so the tooltip doesn't show too often.
// - for items which main purpose is to be hovered, or items with low affordance, or in less consistent apps, prefer no delay or shorter delay.
HoveredFlags_ForTooltip :: HoveredFlags(1<<12) // Shortcut for standard flags when using IsItemHovered() + SetTooltip() sequence.
// (Advanced) Mouse Hovering delays.
// - generally you can use ImGuiHoveredFlags_ForTooltip to use application-standardized flags.
// - use those if you need specific overrides.
HoveredFlags_Stationary    :: HoveredFlags(1<<13) // Require mouse to be stationary for style.HoverStationaryDelay (~0.15 sec) _at least one time_. After this, can move on same item/window. Using the stationary test tends to reduces the need for a long delay.
HoveredFlags_DelayNone     :: HoveredFlags(1<<14) // IsItemHovered() only: Return true immediately (default). As this is the default you generally ignore this.
HoveredFlags_DelayShort    :: HoveredFlags(1<<15) // IsItemHovered() only: Return true after style.HoverDelayShort elapsed (~0.15 sec) (shared between items) + requires mouse to be stationary for style.HoverStationaryDelay (once per item).
HoveredFlags_DelayNormal   :: HoveredFlags(1<<16) // IsItemHovered() only: Return true after style.HoverDelayNormal elapsed (~0.40 sec) (shared between items) + requires mouse to be stationary for style.HoverStationaryDelay (once per item).
HoveredFlags_NoSharedDelay :: HoveredFlags(1<<17) // IsItemHovered() only: Disable shared delay system where moving from one item to the next keeps the previous timer for a short time (standard for tooltips with long delays)

// Flags for ImGui::DockSpace(), shared/inherited by child nodes.
// (Some flags can be applied to individual nodes directly)
// FIXME-DOCK: Also see ImGuiDockNodeFlagsPrivate_ which may involve using the WIP and internal DockBuilder api.
DockNodeFlags :: bit_set[DockNodeFlag; c.int]
DockNodeFlag :: enum c.int {
	KeepAliveOnly = 0, //       // Don't display the dockspace node but keep it alive. Windows docked into this dockspace node won't be undocked.
	//ImGuiDockNodeFlags_NoCentralNode              = 1 << 1,   //       // Disable Central Node (the node which can stay empty)
	NoDockingOverCentralNode = 2, //       // Disable docking over the Central Node, which will be always kept empty.
	PassthruCentralNode      = 3, //       // Enable passthru dockspace: 1) DockSpace() will render a ImGuiCol_WindowBg background covering everything excepted the Central Node when empty. Meaning the host window should probably use SetNextWindowBgAlpha(0.0f) prior to Begin() when using this. 2) When Central Node is empty: let inputs pass-through + won't display a DockingEmptyBg background. See demo for details.
	NoDockingSplit           = 4, //       // Disable other windows/nodes from splitting this node.
	NoResize                 = 5, // Saved // Disable resizing node using the splitter/separators. Useful with programmatically setup dockspaces.
	AutoHideTabBar           = 6, //       // Tab bar will automatically hide when there is a single window in the dock node.
	NoUndocking              = 7, //       // Disable undocking this node.
}


// Flags for ImGui::BeginDragDropSource(), ImGui::AcceptDragDropPayload()
DragDropFlags :: bit_set[DragDropFlag; c.int]
DragDropFlag :: enum c.int {
	// BeginDragDropSource() flags
	SourceNoPreviewTooltip   = 0, // Disable preview tooltip. By default, a successful call to BeginDragDropSource opens a tooltip so you can display a preview or description of the source contents. This flag disables this behavior.
	SourceNoDisableHover     = 1, // By default, when dragging we clear data so that IsItemHovered() will return false, to avoid subsequent user code submitting tooltips. This flag disables this behavior so you can still call IsItemHovered() on the source item.
	SourceNoHoldToOpenOthers = 2, // Disable the behavior that allows to open tree nodes and collapsing header by holding over them while dragging a source item.
	SourceAllowNullID        = 3, // Allow items such as Text(), Image() that have no unique identifier to be used as drag source, by manufacturing a temporary identifier based on their window-relative position. This is extremely unusual within the dear imgui ecosystem and so we made it explicit.
	SourceExtern             = 4, // External source (from outside of dear imgui), won't attempt to read current item/window info. Will always return true. Only one Extern source can be active simultaneously.
	PayloadAutoExpire        = 5, // Automatically expire the payload if the source cease to be submitted (otherwise payloads are persisting while being dragged)
	PayloadNoCrossContext    = 6, // Hint to specify that the payload may not be copied outside current dear imgui context.
	PayloadNoCrossProcess    = 7, // Hint to specify that the payload may not be copied outside current process.
	// AcceptDragDropPayload() flags
	AcceptBeforeDelivery    = 10, // AcceptDragDropPayload() will returns true even before the mouse button is released. You can then call IsDelivery() to test if the payload needs to be delivered.
	AcceptNoDrawDefaultRect = 11, // Do not draw the default highlight rectangle when hovering over target.
	AcceptNoPreviewTooltip  = 12, // Request hiding the BeginDragDropSource tooltip from the BeginDragDropTarget site.
}

DragDropFlags_AcceptPeekOnly :: DragDropFlags{.AcceptBeforeDelivery,.AcceptNoDrawDefaultRect} // For peeking ahead and inspecting the payload before delivery.

// A primary data type
DataType :: enum c.int {
	S8,     // signed char / char (with sensible compilers)
	U8,     // unsigned char
	S16,    // short
	U16,    // unsigned short
	S32,    // int
	U32,    // unsigned int
	S64,    // long long / __int64
	U64,    // unsigned long long / unsigned __int64
	Float,  // float
	Double, // double
	Bool,   // bool (provided for user convenience, not supported by scalar widgets)
	String, // char* (provided for user convenience, not supported by scalar widgets)
	COUNT,
}

// A cardinal direction
Dir :: enum c.int { // Forward declared enum type ImGuiDir
	None = -1,
	Left,
	Right,
	Up,
	Down,
	COUNT,
}

// A sorting direction
SortDirection :: enum c.int { // Forward declared enum type ImGuiSortDirection
	None,
	Ascending,  // Ascending = 0->9, A->Z etc.
	Descending, // Descending = 9->0, Z->A etc.
}

// A key identifier (ImGuiKey_XXX or ImGuiMod_XXX value): can represent Keyboard, Mouse and Gamepad values.
// All our named keys are >= 512. Keys value 0 to 511 are left unused and were legacy native/opaque key values (< 1.87).
// Support for legacy keys was completely removed in 1.91.5.
// Read details about the 1.87+ transition : https://github.com/ocornut/imgui/issues/4921
// Note that "Keys" related to physical keys and are not the same concept as input "Characters", the later are submitted via io.AddInputCharacter().
// The keyboard key enum values are named after the keys on a standard US keyboard, and on other keyboard types the keys reported may not match the keycaps.
Key :: enum c.int { // Forward declared enum type ImGuiKey
	// Keyboard
	None,
	NamedKey_BEGIN = 512, // First valid key value (other than 0)
	Tab = 512,            // == ImGuiKey_NamedKey_BEGIN
	LeftArrow,
	RightArrow,
	UpArrow,
	DownArrow,
	PageUp,
	PageDown,
	Home,
	End,
	Insert,
	Delete,
	Backspace,
	Space,
	Enter,
	Escape,
	LeftCtrl,
	LeftShift,
	LeftAlt,
	LeftSuper,
	RightCtrl,
	RightShift,
	RightAlt,
	RightSuper,
	Menu,
	_0,
	_1,
	_2,
	_3,
	_4,
	_5,
	_6,
	_7,
	_8,
	_9,
	A,
	B,
	C,
	D,
	E,
	F,
	G,
	H,
	I,
	J,
	K,
	L,
	M,
	N,
	O,
	P,
	Q,
	R,
	S,
	T,
	U,
	V,
	W,
	X,
	Y,
	Z,
	F1,
	F2,
	F3,
	F4,
	F5,
	F6,
	F7,
	F8,
	F9,
	F10,
	F11,
	F12,
	F13,
	F14,
	F15,
	F16,
	F17,
	F18,
	F19,
	F20,
	F21,
	F22,
	F23,
	F24,
	Apostrophe,           // '
	Comma,                // ,
	Minus,                // -
	Period,               // .
	Slash,                // /
	Semicolon,            // ;
	Equal,                // =
	LeftBracket,          // [
	Backslash,            // \ (this text inhibit multiline comment caused by backslash)
	RightBracket,         // ]
	GraveAccent,          // `
	CapsLock,
	ScrollLock,
	NumLock,
	PrintScreen,
	Pause,
	Keypad0,
	Keypad1,
	Keypad2,
	Keypad3,
	Keypad4,
	Keypad5,
	Keypad6,
	Keypad7,
	Keypad8,
	Keypad9,
	KeypadDecimal,
	KeypadDivide,
	KeypadMultiply,
	KeypadSubtract,
	KeypadAdd,
	KeypadEnter,
	KeypadEqual,
	AppBack,              // Available on some keyboard/mouses. Often referred as "Browser Back"
	AppForward,
	// Gamepad (some of those are analog values, 0.0f to 1.0f)                          // NAVIGATION ACTION
	// (download controller mapping PNG/PSD at http://dearimgui.com/controls_sheets)
	GamepadStart,       // Menu (Xbox)      + (Switch)   Start/Options (PS)
	GamepadBack,        // View (Xbox)      - (Switch)   Share (PS)
	GamepadFaceLeft,    // X (Xbox)         Y (Switch)   Square (PS)        // Tap: Toggle Menu. Hold: Windowing mode (Focus/Move/Resize windows)
	GamepadFaceRight,   // B (Xbox)         A (Switch)   Circle (PS)        // Cancel / Close / Exit
	GamepadFaceUp,      // Y (Xbox)         X (Switch)   Triangle (PS)      // Text Input / On-screen Keyboard
	GamepadFaceDown,    // A (Xbox)         B (Switch)   Cross (PS)         // Activate / Open / Toggle / Tweak
	GamepadDpadLeft,    // D-pad Left                                       // Move / Tweak / Resize Window (in Windowing mode)
	GamepadDpadRight,   // D-pad Right                                      // Move / Tweak / Resize Window (in Windowing mode)
	GamepadDpadUp,      // D-pad Up                                         // Move / Tweak / Resize Window (in Windowing mode)
	GamepadDpadDown,    // D-pad Down                                       // Move / Tweak / Resize Window (in Windowing mode)
	GamepadL1,          // L Bumper (Xbox)  L (Switch)   L1 (PS)            // Tweak Slower / Focus Previous (in Windowing mode)
	GamepadR1,          // R Bumper (Xbox)  R (Switch)   R1 (PS)            // Tweak Faster / Focus Next (in Windowing mode)
	GamepadL2,          // L Trig. (Xbox)   ZL (Switch)  L2 (PS) [Analog]
	GamepadR2,          // R Trig. (Xbox)   ZR (Switch)  R2 (PS) [Analog]
	GamepadL3,          // L Stick (Xbox)   L3 (Switch)  L3 (PS)
	GamepadR3,          // R Stick (Xbox)   R3 (Switch)  R3 (PS)
	GamepadLStickLeft,  // [Analog]                                         // Move Window (in Windowing mode)
	GamepadLStickRight, // [Analog]                                         // Move Window (in Windowing mode)
	GamepadLStickUp,    // [Analog]                                         // Move Window (in Windowing mode)
	GamepadLStickDown,  // [Analog]                                         // Move Window (in Windowing mode)
	GamepadRStickLeft,  // [Analog]
	GamepadRStickRight, // [Analog]
	GamepadRStickUp,    // [Analog]
	GamepadRStickDown,  // [Analog]
	// Aliases: Mouse Buttons (auto-submitted from AddMouseButtonEvent() calls)
	// - This is mirroring the data also written to io.MouseDown[], io.MouseWheel, in a format allowing them to be accessed via standard key API.
	MouseLeft,
	MouseRight,
	MouseMiddle,
	MouseX1,
	MouseX2,
	MouseWheelX,
	MouseWheelY,
	// [Internal] Reserved for mod storage
	ReservedForModCtrl,
	ReservedForModShift,
	ReservedForModAlt,
	ReservedForModSuper,
	NamedKey_END,
	// Keyboard Modifiers (explicitly submitted by backend via AddKeyEvent() calls)
	// - This is mirroring the data also written to io.KeyCtrl, io.KeyShift, io.KeyAlt, io.KeySuper, in a format allowing
	//   them to be accessed via standard key API, allowing calls such as IsKeyPressed(), IsKeyReleased(), querying duration etc.
	// - Code polling every key (e.g. an interface to detect a key press for input mapping) might want to ignore those
	//   and prefer using the real keys (e.g. ImGuiKey_LeftCtrl, ImGuiKey_RightCtrl instead of ImGuiMod_Ctrl).
	// - In theory the value of keyboard modifiers should be roughly equivalent to a logical or of the equivalent left/right keys.
	//   In practice: it's complicated; mods are often provided from different sources. Keyboard layout, IME, sticky keys and
	//   backends tend to interfere and break that equivalence. The safer decision is to relay that ambiguity down to the end-user...
	// - On macOS, we swap Cmd(Super) and Ctrl keys at the time of the io.AddKeyEvent() call.
	ImGuiMod_None = 0,
	ImGuiMod_Ctrl = 4096,   // Ctrl (non-macOS), Cmd (macOS)
	ImGuiMod_Shift = 8192,  // Shift
	ImGuiMod_Alt = 16384,   // Option/Menu
	ImGuiMod_Super = 32768, // Windows/Super (non-macOS), Ctrl (macOS)
	ImGuiMod_Mask_ = 61440, // 4-bits
	// [Internal] If you need to iterate all keys (for e.g. an input mapper) you may use ImGuiKey_NamedKey_BEGIN..ImGuiKey_NamedKey_END.
	NamedKey_COUNT = 154,
}

// Flags for Shortcut(), SetNextItemShortcut(),
// (and for upcoming extended versions of IsKeyPressed(), IsMouseClicked(), Shortcut(), SetKeyOwner(), SetItemKeyOwner() that are still in imgui_internal.h)
// Don't mistake with ImGuiInputTextFlags! (which is for ImGui::InputText() function)
InputFlags :: bit_set[InputFlag; c.int]
InputFlag :: enum c.int {
	Repeat = 0, // Enable repeat. Return true on successive repeats. Default for legacy IsKeyPressed(). NOT Default for legacy IsMouseClicked(). MUST BE == 1.
	// Flags for Shortcut(), SetNextItemShortcut()
	// - Routing policies: RouteGlobal+OverActive >> RouteActive or RouteFocused (if owner is active item) >> RouteGlobal+OverFocused >> RouteFocused (if in focused window stack) >> RouteGlobal.
	// - Default policy is RouteFocused. Can select only 1 policy among all available.
	RouteActive  = 10, // Route to active item only.
	RouteFocused = 11, // Route to windows in the focus stack (DEFAULT). Deep-most focused window takes inputs. Active item takes inputs over deep-most focused window.
	RouteGlobal  = 12, // Global route (unless a focused window or active item registered the route).
	RouteAlways  = 13, // Do not register route, poll keys directly.
	// - Routing options
	RouteOverFocused     = 14, // Option: global route: higher priority than focused route (unless active item in focused route).
	RouteOverActive      = 15, // Option: global route: higher priority than active item. Unlikely you need to use that: will interfere with every active items, e.g. CTRL+A registered by InputText will be overridden by this. May not be fully honored as user/internal code is likely to always assume they can access keys when active.
	RouteUnlessBgFocused = 16, // Option: global route: will not be applied if underlying background/void is focused (== no Dear ImGui windows are focused). Useful for overlay applications.
	RouteFromRootWindow  = 17, // Option: route evaluated from the point of view of root window rather than current window.
	// Flags for SetNextItemShortcut()
	Tooltip = 18, // Automatically display a tooltip when hovering item [BETA] Unsure of right api (opt-in/opt-out)
}


// Configuration flags stored in io.ConfigFlags. Set by user/application.
ConfigFlags :: bit_set[ConfigFlag; c.int]
ConfigFlag :: enum c.int {
	NavEnableKeyboard   = 0, // Master keyboard navigation enable flag. Enable full Tabbing + directional arrows + space/enter to activate.
	NavEnableGamepad    = 1, // Master gamepad navigation enable flag. Backend also needs to set ImGuiBackendFlags_HasGamepad.
	NoMouse             = 4, // Instruct dear imgui to disable mouse inputs and interactions.
	NoMouseCursorChange = 5, // Instruct backend to not alter mouse cursor shape and visibility. Use if the backend cursor changes are interfering with yours and you don't want to use SetMouseCursor() to change mouse cursor. You may want to honor requests from imgui by reading GetMouseCursor() yourself instead.
	NoKeyboard          = 6, // Instruct dear imgui to disable keyboard inputs and interactions. This is done by ignoring keyboard events and clearing existing states.
	// [BETA] Docking
	DockingEnable = 7, // Docking enable flags.
	// [BETA] Viewports
	// When using viewports it is recommended that your default value for ImGuiCol_WindowBg is opaque (Alpha=1.0) so transition to a viewport won't be noticeable.
	ViewportsEnable         = 10, // Viewport enable flags (require both ImGuiBackendFlags_PlatformHasViewports + ImGuiBackendFlags_RendererHasViewports set by the respective backends)
	DpiEnableScaleViewports = 14, // [BETA: Don't use] FIXME-DPI: Reposition and resize imgui windows when the DpiScale of a viewport changed (mostly useful for the main viewport hosting other window). Note that resizing the main window itself is up to your application.
	DpiEnableScaleFonts     = 15, // [BETA: Don't use] FIXME-DPI: Request bitmap-scaled fonts to match DpiScale. This is a very low-quality workaround. The correct way to handle DPI is _currently_ to replace the atlas and/or fonts in the Platform_OnChangedViewport callback, but this is all early work in progress.
	// User storage (to allow your backend/engine to communicate to code that may be shared between multiple projects. Those flags are NOT used by core Dear ImGui)
	IsSRGB        = 20, // Application is SRGB-aware.
	IsTouchScreen = 21, // Application is using a touch screen instead of a mouse.
}


// Backend capabilities flags stored in io.BackendFlags. Set by imgui_impl_xxx or custom backend.
BackendFlags :: bit_set[BackendFlag; c.int]
BackendFlag :: enum c.int {
	HasGamepad           = 0, // Backend Platform supports gamepad and currently has one connected.
	HasMouseCursors      = 1, // Backend Platform supports honoring GetMouseCursor() value to change the OS cursor shape.
	HasSetMousePos       = 2, // Backend Platform supports io.WantSetMousePos requests to reposition the OS mouse position (only used if io.ConfigNavMoveSetMousePos is set).
	RendererHasVtxOffset = 3, // Backend Renderer supports ImDrawCmd::VtxOffset. This enables output of large meshes (64K+ vertices) while still using 16-bit indices.
	// [BETA] Viewports
	PlatformHasViewports    = 10, // Backend Platform supports multiple viewports.
	HasMouseHoveredViewport = 11, // Backend Platform supports calling io.AddMouseViewportEvent() with the viewport under the mouse. IF POSSIBLE, ignore viewports with the ImGuiViewportFlags_NoInputs flag (Win32 backend, GLFW 3.30+ backend can do this, SDL backend cannot). If this cannot be done, Dear ImGui needs to use a flawed heuristic to find the viewport under.
	RendererHasViewports    = 12, // Backend Renderer supports multiple viewports.
}


// Enumeration for PushStyleColor() / PopStyleColor()
Col :: enum c.int {
	Text,
	TextDisabled,
	WindowBg,                  // Background of normal windows
	ChildBg,                   // Background of child windows
	PopupBg,                   // Background of popups, menus, tooltips windows
	Border,
	BorderShadow,
	FrameBg,                   // Background of checkbox, radio button, plot, slider, text input
	FrameBgHovered,
	FrameBgActive,
	TitleBg,                   // Title bar
	TitleBgActive,             // Title bar when focused
	TitleBgCollapsed,          // Title bar when collapsed
	MenuBarBg,
	ScrollbarBg,
	ScrollbarGrab,
	ScrollbarGrabHovered,
	ScrollbarGrabActive,
	CheckMark,                 // Checkbox tick and RadioButton circle
	SliderGrab,
	SliderGrabActive,
	Button,
	ButtonHovered,
	ButtonActive,
	Header,                    // Header* colors are used for CollapsingHeader, TreeNode, Selectable, MenuItem
	HeaderHovered,
	HeaderActive,
	Separator,
	SeparatorHovered,
	SeparatorActive,
	ResizeGrip,                // Resize grip in lower-right and lower-left corners of windows.
	ResizeGripHovered,
	ResizeGripActive,
	TabHovered,                // Tab background, when hovered
	Tab,                       // Tab background, when tab-bar is focused & tab is unselected
	TabSelected,               // Tab background, when tab-bar is focused & tab is selected
	TabSelectedOverline,       // Tab horizontal overline, when tab-bar is focused & tab is selected
	TabDimmed,                 // Tab background, when tab-bar is unfocused & tab is unselected
	TabDimmedSelected,         // Tab background, when tab-bar is unfocused & tab is selected
	TabDimmedSelectedOverline, //..horizontal overline, when tab-bar is unfocused & tab is selected
	DockingPreview,            // Preview overlay color when about to docking something
	DockingEmptyBg,            // Background color for empty node (e.g. CentralNode with no window docked into it)
	PlotLines,
	PlotLinesHovered,
	PlotHistogram,
	PlotHistogramHovered,
	TableHeaderBg,             // Table header background
	TableBorderStrong,         // Table outer and header borders (prefer using Alpha=1.0 here)
	TableBorderLight,          // Table inner borders (prefer using Alpha=1.0 here)
	TableRowBg,                // Table row background (even rows)
	TableRowBgAlt,             // Table row background (odd rows)
	TextLink,                  // Hyperlink color
	TextSelectedBg,
	DragDropTarget,            // Rectangle highlighting a drop target
	NavCursor,                 // Color of keyboard/gamepad navigation cursor/rectangle, when visible
	NavWindowingHighlight,     // Highlight window when using CTRL+TAB
	NavWindowingDimBg,         // Darken/colorize entire screen behind the CTRL+TAB window list, when active
	ModalWindowDimBg,          // Darken/colorize entire screen behind a modal window, when one is active
	COUNT,
}

// Enumeration for PushStyleVar() / PopStyleVar() to temporarily modify the ImGuiStyle structure.
// - The enum only refers to fields of ImGuiStyle which makes sense to be pushed/popped inside UI code.
//   During initialization or between frames, feel free to just poke into ImGuiStyle directly.
// - Tip: Use your programming IDE navigation facilities on the names in the _second column_ below to find the actual members and their description.
//   - In Visual Studio: CTRL+comma ("Edit.GoToAll") can follow symbols inside comments, whereas CTRL+F12 ("Edit.GoToImplementation") cannot.
//   - In Visual Studio w/ Visual Assist installed: ALT+G ("VAssistX.GoToImplementation") can also follow symbols inside comments.
//   - In VS Code, CLion, etc.: CTRL+click can follow symbols inside comments.
// - When changing this enum, you need to update the associated internal table GStyleVarInfo[] accordingly. This is where we link enum values to members offset/type.
StyleVar :: enum c.int {
	// Enum name -------------------------- // Member in ImGuiStyle structure (see ImGuiStyle for descriptions)
	Alpha,                       // float     Alpha
	DisabledAlpha,               // float     DisabledAlpha
	WindowPadding,               // ImVec2    WindowPadding
	WindowRounding,              // float     WindowRounding
	WindowBorderSize,            // float     WindowBorderSize
	WindowMinSize,               // ImVec2    WindowMinSize
	WindowTitleAlign,            // ImVec2    WindowTitleAlign
	ChildRounding,               // float     ChildRounding
	ChildBorderSize,             // float     ChildBorderSize
	PopupRounding,               // float     PopupRounding
	PopupBorderSize,             // float     PopupBorderSize
	FramePadding,                // ImVec2    FramePadding
	FrameRounding,               // float     FrameRounding
	FrameBorderSize,             // float     FrameBorderSize
	ItemSpacing,                 // ImVec2    ItemSpacing
	ItemInnerSpacing,            // ImVec2    ItemInnerSpacing
	IndentSpacing,               // float     IndentSpacing
	CellPadding,                 // ImVec2    CellPadding
	ScrollbarSize,               // float     ScrollbarSize
	ScrollbarRounding,           // float     ScrollbarRounding
	GrabMinSize,                 // float     GrabMinSize
	GrabRounding,                // float     GrabRounding
	TabRounding,                 // float     TabRounding
	TabBorderSize,               // float     TabBorderSize
	TabBarBorderSize,            // float     TabBarBorderSize
	TabBarOverlineSize,          // float     TabBarOverlineSize
	TableAngledHeadersAngle,     // float     TableAngledHeadersAngle
	TableAngledHeadersTextAlign, // ImVec2  TableAngledHeadersTextAlign
	ButtonTextAlign,             // ImVec2    ButtonTextAlign
	SelectableTextAlign,         // ImVec2    SelectableTextAlign
	SeparatorTextBorderSize,     // float     SeparatorTextBorderSize
	SeparatorTextAlign,          // ImVec2    SeparatorTextAlign
	SeparatorTextPadding,        // ImVec2    SeparatorTextPadding
	DockingSeparatorSize,        // float     DockingSeparatorSize
	COUNT,
}

// Flags for InvisibleButton() [extended in imgui_internal.h]
ButtonFlags :: bit_set[ButtonFlag; c.int]
ButtonFlag :: enum c.int {
	MouseButtonLeft   = 0, // React on left mouse button (default)
	MouseButtonRight  = 1, // React on right mouse button
	MouseButtonMiddle = 2, // React on center mouse button
	EnableNav         = 3, // InvisibleButton(): do not disable navigation/tabbing. Otherwise disabled by default.
}

ButtonFlags_MouseButtonMask_ :: ButtonFlags{.MouseButtonLeft,.MouseButtonRight,.MouseButtonMiddle} // [Internal]

// Flags for ColorEdit3() / ColorEdit4() / ColorPicker3() / ColorPicker4() / ColorButton()
ColorEditFlags :: bit_set[ColorEditFlag; c.int]
ColorEditFlag :: enum c.int {
	NoAlpha        = 1,  //              // ColorEdit, ColorPicker, ColorButton: ignore Alpha component (will only read 3 components from the input pointer).
	NoPicker       = 2,  //              // ColorEdit: disable picker when clicking on color square.
	NoOptions      = 3,  //              // ColorEdit: disable toggling options menu when right-clicking on inputs/small preview.
	NoSmallPreview = 4,  //              // ColorEdit, ColorPicker: disable color square preview next to the inputs. (e.g. to show only the inputs)
	NoInputs       = 5,  //              // ColorEdit, ColorPicker: disable inputs sliders/text widgets (e.g. to show only the small preview color square).
	NoTooltip      = 6,  //              // ColorEdit, ColorPicker, ColorButton: disable tooltip when hovering the preview.
	NoLabel        = 7,  //              // ColorEdit, ColorPicker: disable display of inline text label (the label is still forwarded to the tooltip and picker).
	NoSidePreview  = 8,  //              // ColorPicker: disable bigger color preview on right side of the picker, use small color square preview instead.
	NoDragDrop     = 9,  //              // ColorEdit: disable drag and drop target. ColorButton: disable drag and drop source.
	NoBorder       = 10, //              // ColorButton: disable border (which is enforced by default)
	// User Options (right-click on widget to change some of them).
	AlphaBar         = 16, //              // ColorEdit, ColorPicker: show vertical alpha bar/gradient in picker.
	AlphaPreview     = 17, //              // ColorEdit, ColorPicker, ColorButton: display preview as a transparent color over a checkerboard, instead of opaque.
	AlphaPreviewHalf = 18, //              // ColorEdit, ColorPicker, ColorButton: display half opaque / half checkerboard, instead of opaque.
	HDR              = 19, //              // (WIP) ColorEdit: Currently only disable 0.0f..1.0f limits in RGBA edition (note: you probably want to use ImGuiColorEditFlags_Float flag as well).
	DisplayRGB       = 20, // [Display]    // ColorEdit: override _display_ type among RGB/HSV/Hex. ColorPicker: select any combination using one or more of RGB/HSV/Hex.
	DisplayHSV       = 21, // [Display]    // "
	DisplayHex       = 22, // [Display]    // "
	Uint8            = 23, // [DataType]   // ColorEdit, ColorPicker, ColorButton: _display_ values formatted as 0..255.
	Float            = 24, // [DataType]   // ColorEdit, ColorPicker, ColorButton: _display_ values formatted as 0.0f..1.0f floats instead of 0..255 integers. No round-trip of value via integers.
	PickerHueBar     = 25, // [Picker]     // ColorPicker: bar for Hue, rectangle for Sat/Value.
	PickerHueWheel   = 26, // [Picker]     // ColorPicker: wheel for Hue, triangle for Sat/Value.
	InputRGB         = 27, // [Input]      // ColorEdit, ColorPicker: input and output data in RGB format.
	InputHSV         = 28, // [Input]      // ColorEdit, ColorPicker: input and output data in HSV format.
}

// Defaults Options. You can set application defaults using SetColorEditOptions(). The intent is that you probably don't want to
// override them in most of your calls. Let the user choose via the option menu and/or call SetColorEditOptions() once during startup.
ColorEditFlags_DefaultOptions_ :: ColorEditFlags{.Uint8,.DisplayRGB,.InputRGB,.PickerHueBar}
// [Internal] Masks
ColorEditFlags_DisplayMask_  :: ColorEditFlags{.DisplayRGB,.DisplayHSV,.DisplayHex}
ColorEditFlags_DataTypeMask_ :: ColorEditFlags{.Uint8,.Float}
ColorEditFlags_PickerMask_   :: ColorEditFlags{.PickerHueWheel,.PickerHueBar}
ColorEditFlags_InputMask_    :: ColorEditFlags{.InputRGB,.InputHSV}

// Flags for DragFloat(), DragInt(), SliderFloat(), SliderInt() etc.
// We use the same sets of flags for DragXXX() and SliderXXX() functions as the features are the same and it makes it easier to swap them.
// (Those are per-item flags. There is shared behavior flag too: ImGuiIO: io.ConfigDragClickToInputText)
SliderFlags :: bit_set[SliderFlag; c.int]
SliderFlag :: enum c.int {
	Logarithmic     = 5,  // Make the widget logarithmic (linear otherwise). Consider using ImGuiSliderFlags_NoRoundToFormat with this if using a format-string with small amount of digits.
	NoRoundToFormat = 6,  // Disable rounding underlying value to match precision of the display format string (e.g. %.3f values are rounded to those 3 digits).
	NoInput         = 7,  // Disable CTRL+Click or Enter key allowing to input text directly into the widget.
	WrapAround      = 8,  // Enable wrapping around from max to min and from min to max. Only supported by DragXXX() functions for now.
	ClampOnInput    = 9,  // Clamp value to min/max bounds when input manually with CTRL+Click. By default CTRL+Click allows going out of bounds.
	ClampZeroRange  = 10, // Clamp even if min==max==0.0f. Otherwise due to legacy reason DragXXX functions don't clamp with those values. When your clamping limits are dynamic you almost always want to use it.
	NoSpeedTweaks   = 11, // Disable keyboard modifiers altering tweak speed. Useful if you want to alter tweak speed yourself based on your own logic.
}

SliderFlags_AlwaysClamp  :: SliderFlags{.ClampOnInput,.ClampZeroRange}
SliderFlags_InvalidMask_ :: c.int(0x7000000F) // Meant to be of type SliderFlags // [Internal] We treat using those bits as being potentially a 'float power' argument from the previous API that has got miscast to this enum, and will trigger an assert if needed.

// Identify a mouse button.
// Those values are guaranteed to be stable and we frequently use 0/1 directly. Named enums provided for convenience.
MouseButton :: enum c.int {
	Left,
	Right,
	Middle,
	COUNT = 5,
}

// Enumeration for GetMouseCursor()
// User code may request backend to display given cursor by calling SetMouseCursor(), which is why we have some cursors that are marked unused here
MouseCursor :: enum c.int {
	None = -1,
	Arrow,
	TextInput,  // When hovering over InputText, etc.
	ResizeAll,  // (Unused by Dear ImGui functions)
	ResizeNS,   // When hovering over a horizontal border
	ResizeEW,   // When hovering over a vertical border or a column
	ResizeNESW, // When hovering over the bottom-left corner of a window
	ResizeNWSE, // When hovering over the bottom-right corner of a window
	Hand,       // (Unused by Dear ImGui functions. Use for e.g. hyperlinks)
	NotAllowed, // When hovering something with disallowed interaction. Usually a crossed circle.
	COUNT,
}

// Enumeration for AddMouseSourceEvent() actual source of Mouse Input data.
// Historically we use "Mouse" terminology everywhere to indicate pointer data, e.g. MousePos, IsMousePressed(), io.AddMousePosEvent()
// But that "Mouse" data can come from different source which occasionally may be useful for application to know about.
// You can submit a change of pointer type using io.AddMouseSourceEvent().
MouseSource :: enum c.int { // Forward declared enum type ImGuiMouseSource
	Mouse,       // Input is coming from an actual mouse.
	TouchScreen, // Input is coming from a touch screen (no hovering prior to initial press, less precise initial press aiming, dual-axis wheeling possible).
	Pen,         // Input is coming from a pressure/magnetic pen (often used in conjunction with high-sampling rates).
	COUNT,
}

// Enumeration for ImGui::SetNextWindow***(), SetWindow***(), SetNextItem***() functions
// Represent a condition.
// Important: Treat as a regular enum! Do NOT combine multiple values using binary operators! All the functions above treat 0 as a shortcut to ImGuiCond_Always.
Cond :: enum c.int {
	None,             // No condition (always set the variable), same as _Always
	Always,           // No condition (always set the variable), same as _None
	Once,             // Set the variable once per runtime session (only the first call will succeed)
	FirstUseEver = 4, // Set the variable if the object/window has no persistently saved data (no entry in .ini file)
	Appearing = 8,    // Set the variable if the object/window is appearing after being hidden/inactive (or the first time)
}

// Flags for ImGui::BeginTable()
// - Important! Sizing policies have complex and subtle side effects, much more so than you would expect.
//   Read comments/demos carefully + experiment with live demos to get acquainted with them.
// - The DEFAULT sizing policies are:
//    - Default to ImGuiTableFlags_SizingFixedFit    if ScrollX is on, or if host window has ImGuiWindowFlags_AlwaysAutoResize.
//    - Default to ImGuiTableFlags_SizingStretchSame if ScrollX is off.
// - When ScrollX is off:
//    - Table defaults to ImGuiTableFlags_SizingStretchSame -> all Columns defaults to ImGuiTableColumnFlags_WidthStretch with same weight.
//    - Columns sizing policy allowed: Stretch (default), Fixed/Auto.
//    - Fixed Columns (if any) will generally obtain their requested width (unless the table cannot fit them all).
//    - Stretch Columns will share the remaining width according to their respective weight.
//    - Mixed Fixed/Stretch columns is possible but has various side-effects on resizing behaviors.
//      The typical use of mixing sizing policies is: any number of LEADING Fixed columns, followed by one or two TRAILING Stretch columns.
//      (this is because the visible order of columns have subtle but necessary effects on how they react to manual resizing).
// - When ScrollX is on:
//    - Table defaults to ImGuiTableFlags_SizingFixedFit -> all Columns defaults to ImGuiTableColumnFlags_WidthFixed
//    - Columns sizing policy allowed: Fixed/Auto mostly.
//    - Fixed Columns can be enlarged as needed. Table will show a horizontal scrollbar if needed.
//    - When using auto-resizing (non-resizable) fixed columns, querying the content width to use item right-alignment e.g. SetNextItemWidth(-FLT_MIN) doesn't make sense, would create a feedback loop.
//    - Using Stretch columns OFTEN DOES NOT MAKE SENSE if ScrollX is on, UNLESS you have specified a value for 'inner_width' in BeginTable().
//      If you specify a value for 'inner_width' then effectively the scrolling space is known and Stretch or mixed Fixed/Stretch columns become meaningful again.
// - Read on documentation at the top of imgui_tables.cpp for details.
TableFlags :: distinct c.int
// Features
TableFlags_None              :: TableFlags(0)
TableFlags_Resizable         :: TableFlags(1<<0) // Enable resizing columns.
TableFlags_Reorderable       :: TableFlags(1<<1) // Enable reordering columns in header row (need calling TableSetupColumn() + TableHeadersRow() to display headers)
TableFlags_Hideable          :: TableFlags(1<<2) // Enable hiding/disabling columns in context menu.
TableFlags_Sortable          :: TableFlags(1<<3) // Enable sorting. Call TableGetSortSpecs() to obtain sort specs. Also see ImGuiTableFlags_SortMulti and ImGuiTableFlags_SortTristate.
TableFlags_NoSavedSettings   :: TableFlags(1<<4) // Disable persisting columns order, width and sort settings in the .ini file.
TableFlags_ContextMenuInBody :: TableFlags(1<<5) // Right-click on columns body/contents will display table context menu. By default it is available in TableHeadersRow().
// Decorations
TableFlags_RowBg                      :: TableFlags(1<<6)                                                // Set each RowBg color with ImGuiCol_TableRowBg or ImGuiCol_TableRowBgAlt (equivalent of calling TableSetBgColor with ImGuiTableBgFlags_RowBg0 on each row manually)
TableFlags_BordersInnerH              :: TableFlags(1<<7)                                                // Draw horizontal borders between rows.
TableFlags_BordersOuterH              :: TableFlags(1<<8)                                                // Draw horizontal borders at the top and bottom.
TableFlags_BordersInnerV              :: TableFlags(1<<9)                                                // Draw vertical borders between columns.
TableFlags_BordersOuterV              :: TableFlags(1<<10)                                               // Draw vertical borders on the left and right sides.
TableFlags_BordersH                   :: TableFlags(TableFlags_BordersInnerH | TableFlags_BordersOuterH) // Draw horizontal borders.
TableFlags_BordersV                   :: TableFlags(TableFlags_BordersInnerV | TableFlags_BordersOuterV) // Draw vertical borders.
TableFlags_BordersInner               :: TableFlags(TableFlags_BordersInnerV | TableFlags_BordersInnerH) // Draw inner borders.
TableFlags_BordersOuter               :: TableFlags(TableFlags_BordersOuterV | TableFlags_BordersOuterH) // Draw outer borders.
TableFlags_Borders                    :: TableFlags(TableFlags_BordersInner | TableFlags_BordersOuter)   // Draw all borders.
TableFlags_NoBordersInBody            :: TableFlags(1<<11)                                               // [ALPHA] Disable vertical borders in columns Body (borders will always appear in Headers). -> May move to style
TableFlags_NoBordersInBodyUntilResize :: TableFlags(1<<12)                                               // [ALPHA] Disable vertical borders in columns Body until hovered for resize (borders will always appear in Headers). -> May move to style
// Sizing Policy (read above for defaults)
TableFlags_SizingFixedFit    :: TableFlags(1<<13) // Columns default to _WidthFixed or _WidthAuto (if resizable or not resizable), matching contents width.
TableFlags_SizingFixedSame   :: TableFlags(2<<13) // Columns default to _WidthFixed or _WidthAuto (if resizable or not resizable), matching the maximum contents width of all columns. Implicitly enable ImGuiTableFlags_NoKeepColumnsVisible.
TableFlags_SizingStretchProp :: TableFlags(3<<13) // Columns default to _WidthStretch with default weights proportional to each columns contents widths.
TableFlags_SizingStretchSame :: TableFlags(4<<13) // Columns default to _WidthStretch with default weights all equal, unless overridden by TableSetupColumn().
// Sizing Extra Options
TableFlags_NoHostExtendX        :: TableFlags(1<<16) // Make outer width auto-fit to columns, overriding outer_size.x value. Only available when ScrollX/ScrollY are disabled and Stretch columns are not used.
TableFlags_NoHostExtendY        :: TableFlags(1<<17) // Make outer height stop exactly at outer_size.y (prevent auto-extending table past the limit). Only available when ScrollX/ScrollY are disabled. Data below the limit will be clipped and not visible.
TableFlags_NoKeepColumnsVisible :: TableFlags(1<<18) // Disable keeping column always minimally visible when ScrollX is off and table gets too small. Not recommended if columns are resizable.
TableFlags_PreciseWidths        :: TableFlags(1<<19) // Disable distributing remainder width to stretched columns (width allocation on a 100-wide table with 3 columns: Without this flag: 33,33,34. With this flag: 33,33,33). With larger number of columns, resizing will appear to be less smooth.
// Clipping
TableFlags_NoClip :: TableFlags(1<<20) // Disable clipping rectangle for every individual columns (reduce draw command count, items will be able to overflow into other columns). Generally incompatible with TableSetupScrollFreeze().
// Padding
TableFlags_PadOuterX   :: TableFlags(1<<21) // Default if BordersOuterV is on. Enable outermost padding. Generally desirable if you have headers.
TableFlags_NoPadOuterX :: TableFlags(1<<22) // Default if BordersOuterV is off. Disable outermost padding.
TableFlags_NoPadInnerX :: TableFlags(1<<23) // Disable inner padding between columns (double inner padding if BordersOuterV is on, single inner padding if BordersOuterV is off).
// Scrolling
TableFlags_ScrollX :: TableFlags(1<<24) // Enable horizontal scrolling. Require 'outer_size' parameter of BeginTable() to specify the container size. Changes default sizing policy. Because this creates a child window, ScrollY is currently generally recommended when using ScrollX.
TableFlags_ScrollY :: TableFlags(1<<25) // Enable vertical scrolling. Require 'outer_size' parameter of BeginTable() to specify the container size.
// Sorting
TableFlags_SortMulti    :: TableFlags(1<<26) // Hold shift when clicking headers to sort on multiple column. TableGetSortSpecs() may return specs where (SpecsCount > 1).
TableFlags_SortTristate :: TableFlags(1<<27) // Allow no sorting, disable default sorting. TableGetSortSpecs() may return specs where (SpecsCount == 0).
// Miscellaneous
TableFlags_HighlightHoveredColumn :: TableFlags(1<<28) // Highlight column headers when hovered (may evolve into a fuller highlight)
// [Internal] Combinations and masks
TableFlags_SizingMask_ :: TableFlags(TableFlags_SizingFixedFit | TableFlags_SizingFixedSame | TableFlags_SizingStretchProp | TableFlags_SizingStretchSame)

// Flags for ImGui::TableSetupColumn()
TableColumnFlags :: bit_set[TableColumnFlag; c.int]
TableColumnFlag :: enum c.int {
	Disabled             = 0,  // Overriding/master disable flag: hide column, won't show in context menu (unlike calling TableSetColumnEnabled() which manipulates the user accessible state)
	DefaultHide          = 1,  // Default as a hidden/disabled column.
	DefaultSort          = 2,  // Default as a sorting column.
	WidthStretch         = 3,  // Column will stretch. Preferable with horizontal scrolling disabled (default if table sizing policy is _SizingStretchSame or _SizingStretchProp).
	WidthFixed           = 4,  // Column will not stretch. Preferable with horizontal scrolling enabled (default if table sizing policy is _SizingFixedFit and table is resizable).
	NoResize             = 5,  // Disable manual resizing.
	NoReorder            = 6,  // Disable manual reordering this column, this will also prevent other columns from crossing over this column.
	NoHide               = 7,  // Disable ability to hide/disable this column.
	NoClip               = 8,  // Disable clipping for this column (all NoClip columns will render in a same draw command).
	NoSort               = 9,  // Disable ability to sort on this field (even if ImGuiTableFlags_Sortable is set on the table).
	NoSortAscending      = 10, // Disable ability to sort in the ascending direction.
	NoSortDescending     = 11, // Disable ability to sort in the descending direction.
	NoHeaderLabel        = 12, // TableHeadersRow() will submit an empty label for this column. Convenient for some small columns. Name will still appear in context menu or in angled headers. You may append into this cell by calling TableSetColumnIndex() right after the TableHeadersRow() call.
	NoHeaderWidth        = 13, // Disable header text width contribution to automatic column width.
	PreferSortAscending  = 14, // Make the initial sort direction Ascending when first sorting on this column (default).
	PreferSortDescending = 15, // Make the initial sort direction Descending when first sorting on this column.
	IndentEnable         = 16, // Use current Indent value when entering cell (default for column 0).
	IndentDisable        = 17, // Ignore current Indent value when entering cell (default for columns > 0). Indentation changes _within_ the cell will still be honored.
	AngledHeader         = 18, // TableHeadersRow() will submit an angled header row for this column. Note this will add an extra row.
	// Output status flags, read-only via TableGetColumnFlags()
	IsEnabled       = 24, // Status: is enabled == not hidden by user/api (referred to as "Hide" in _DefaultHide and _NoHide) flags.
	IsVisible       = 25, // Status: is visible == is enabled AND not clipped by scrolling.
	IsSorted        = 26, // Status: is currently part of the sort specs
	IsHovered       = 27, // Status: is hovered by mouse
	NoDirectResize_ = 30, // [Internal] Disable user resizing this column directly (it may however we resized indirectly from its left edge)
}

// [Internal] Combinations and masks
TableColumnFlags_WidthMask_  :: TableColumnFlags{.WidthStretch,.WidthFixed}
TableColumnFlags_IndentMask_ :: TableColumnFlags{.IndentEnable,.IndentDisable}
TableColumnFlags_StatusMask_ :: TableColumnFlags{.IsEnabled,.IsVisible,.IsSorted,.IsHovered}

// Flags for ImGui::TableNextRow()
TableRowFlags :: bit_set[TableRowFlag; c.int]
TableRowFlag :: enum c.int {
	Headers = 0, // Identify header row (set default background color + width of its contents accounted differently for auto column width)
}


// Enum for ImGui::TableSetBgColor()
// Background colors are rendering in 3 layers:
//  - Layer 0: draw with RowBg0 color if set, otherwise draw with ColumnBg0 if set.
//  - Layer 1: draw with RowBg1 color if set, otherwise draw with ColumnBg1 if set.
//  - Layer 2: draw with CellBg color if set.
// The purpose of the two row/columns layers is to let you decide if a background color change should override or blend with the existing color.
// When using ImGuiTableFlags_RowBg on the table, each row has the RowBg0 color automatically set for odd/even rows.
// If you set the color of RowBg0 target, your color will override the existing RowBg0 color.
// If you set the color of RowBg1 or ColumnBg1 target, your color will blend over the RowBg0 color.
TableBgTarget :: enum c.int {
	None,
	RowBg0, // Set row background color 0 (generally used for background, automatically set when ImGuiTableFlags_RowBg is used)
	RowBg1, // Set row background color 1 (generally used for selection marking)
	CellBg, // Set cell background color (top-most color)
}

// Flags for BeginMultiSelect()
MultiSelectFlags :: bit_set[MultiSelectFlag; c.int]
MultiSelectFlag :: enum c.int {
	SingleSelect          = 0,  // Disable selecting more than one item. This is available to allow single-selection code to share same code/logic if desired. It essentially disables the main purpose of BeginMultiSelect() tho!
	NoSelectAll           = 1,  // Disable CTRL+A shortcut to select all.
	NoRangeSelect         = 2,  // Disable Shift+selection mouse/keyboard support (useful for unordered 2D selection). With BoxSelect is also ensure contiguous SetRange requests are not combined into one. This allows not handling interpolation in SetRange requests.
	NoAutoSelect          = 3,  // Disable selecting items when navigating (useful for e.g. supporting range-select in a list of checkboxes).
	NoAutoClear           = 4,  // Disable clearing selection when navigating or selecting another one (generally used with ImGuiMultiSelectFlags_NoAutoSelect. useful for e.g. supporting range-select in a list of checkboxes).
	NoAutoClearOnReselect = 5,  // Disable clearing selection when clicking/selecting an already selected item.
	BoxSelect1d           = 6,  // Enable box-selection with same width and same x pos items (e.g. full row Selectable()). Box-selection works better with little bit of spacing between items hit-box in order to be able to aim at empty space.
	BoxSelect2d           = 7,  // Enable box-selection with varying width or varying x pos items support (e.g. different width labels, or 2D layout/grid). This is slower: alters clipping logic so that e.g. horizontal movements will update selection of normally clipped items.
	BoxSelectNoScroll     = 8,  // Disable scrolling when box-selecting near edges of scope.
	ClearOnEscape         = 9,  // Clear selection when pressing Escape while scope is focused.
	ClearOnClickVoid      = 10, // Clear selection when clicking on empty location within scope.
	ScopeWindow           = 11, // Scope for _BoxSelect and _ClearOnClickVoid is whole window (Default). Use if BeginMultiSelect() covers a whole window or used a single time in same window.
	ScopeRect             = 12, // Scope for _BoxSelect and _ClearOnClickVoid is rectangle encompassing BeginMultiSelect()/EndMultiSelect(). Use if BeginMultiSelect() is called multiple times in same window.
	SelectOnClick         = 13, // Apply selection on mouse down when clicking on unselected item. (Default)
	SelectOnClickRelease  = 14, // Apply selection on mouse release when clicking an unselected item. Allow dragging an unselected item without altering selection.
	//ImGuiMultiSelectFlags_RangeSelect2d       = 1 << 15,  // Shift+Selection uses 2d geometry instead of linear sequence, so possible to use Shift+up/down to select vertically in grid. Analogous to what BoxSelect does.
	NavWrapX = 16, // [Temporary] Enable navigation wrapping on X axis. Provided as a convenience because we don't have a design for the general Nav API for this yet. When the more general feature be public we may obsolete this flag in favor of new one.
}


// Selection request type
SelectionRequestType :: enum c.int {
	None,
	SetAll,   // Request app to clear selection (if Selected==false) or select all items (if Selected==true). We cannot set RangeFirstItem/RangeLastItem as its contents is entirely up to user (not necessarily an index)
	SetRange, // Request app to select/unselect [RangeFirstItem..RangeLastItem] items (inclusive) based on value of Selected. Only EndMultiSelect() request this, app code can read after BeginMultiSelect() and it will always be false.
}

// Flags for ImDrawList functions
// (Legacy: bit 0 must always correspond to ImDrawFlags_Closed to be backward compatible with old API using a bool. Bits 1..3 must be unused)
DrawFlags :: distinct c.int
DrawFlags_None                    :: DrawFlags(0)
DrawFlags_Closed                  :: DrawFlags(1<<0)                                                                                                                                  // PathStroke(), AddPolyline(): specify that shape should be closed (Important: this is always == 1 for legacy reason)
DrawFlags_RoundCornersTopLeft     :: DrawFlags(1<<4)                                                                                                                                  // AddRect(), AddRectFilled(), PathRect(): enable rounding top-left corner only (when rounding > 0.0f, we default to all corners). Was 0x01.
DrawFlags_RoundCornersTopRight    :: DrawFlags(1<<5)                                                                                                                                  // AddRect(), AddRectFilled(), PathRect(): enable rounding top-right corner only (when rounding > 0.0f, we default to all corners). Was 0x02.
DrawFlags_RoundCornersBottomLeft  :: DrawFlags(1<<6)                                                                                                                                  // AddRect(), AddRectFilled(), PathRect(): enable rounding bottom-left corner only (when rounding > 0.0f, we default to all corners). Was 0x04.
DrawFlags_RoundCornersBottomRight :: DrawFlags(1<<7)                                                                                                                                  // AddRect(), AddRectFilled(), PathRect(): enable rounding bottom-right corner only (when rounding > 0.0f, we default to all corners). Wax 0x08.
DrawFlags_RoundCornersNone        :: DrawFlags(1<<8)                                                                                                                                  // AddRect(), AddRectFilled(), PathRect(): disable rounding on all corners (when rounding > 0.0f). This is NOT zero, NOT an implicit flag!
DrawFlags_RoundCornersTop         :: DrawFlags(DrawFlags_RoundCornersTopLeft | DrawFlags_RoundCornersTopRight)
DrawFlags_RoundCornersBottom      :: DrawFlags(DrawFlags_RoundCornersBottomLeft | DrawFlags_RoundCornersBottomRight)
DrawFlags_RoundCornersLeft        :: DrawFlags(DrawFlags_RoundCornersBottomLeft | DrawFlags_RoundCornersTopLeft)
DrawFlags_RoundCornersRight       :: DrawFlags(DrawFlags_RoundCornersBottomRight | DrawFlags_RoundCornersTopRight)
DrawFlags_RoundCornersAll         :: DrawFlags(DrawFlags_RoundCornersTopLeft | DrawFlags_RoundCornersTopRight | DrawFlags_RoundCornersBottomLeft | DrawFlags_RoundCornersBottomRight)
DrawFlags_RoundCornersDefault_    :: DrawFlags(DrawFlags_RoundCornersAll)                                                                                                             // Default to ALL corners if none of the _RoundCornersXX flags are specified.
DrawFlags_RoundCornersMask_       :: DrawFlags(DrawFlags_RoundCornersAll | DrawFlags_RoundCornersNone)

// Flags for ImDrawList instance. Those are set automatically by ImGui:: functions from ImGuiIO settings, and generally not manipulated directly.
// It is however possible to temporarily alter flags between calls to ImDrawList:: functions.
DrawListFlags :: bit_set[DrawListFlag; c.int]
DrawListFlag :: enum c.int {
	AntiAliasedLines       = 0, // Enable anti-aliased lines/borders (*2 the number of triangles for 1.0f wide line or lines thin enough to be drawn using textures, otherwise *3 the number of triangles)
	AntiAliasedLinesUseTex = 1, // Enable anti-aliased lines/borders using textures when possible. Require backend to render with bilinear filtering (NOT point/nearest filtering).
	AntiAliasedFill        = 2, // Enable anti-aliased edge around filled shapes (rounded rectangles, circles).
	AllowVtxOffset         = 3, // Can emit 'VtxOffset > 0' to allow large meshes. Set when 'ImGuiBackendFlags_RendererHasVtxOffset' is enabled.
}


// Flags for ImFontAtlas build
FontAtlasFlags :: bit_set[FontAtlasFlag; c.int]
FontAtlasFlag :: enum c.int {
	NoPowerOfTwoHeight = 0, // Don't round the height to next power of two
	NoMouseCursors     = 1, // Don't build software mouse cursors into the atlas (save a little texture memory)
	NoBakedLines       = 2, // Don't build thick line textures into the atlas (save a little texture memory, allow support for point/nearest filtering). The AntiAliasedLinesUseTex features uses them, otherwise they will be rendered using polygons (more expensive for CPU/GPU).
}


// Flags stored in ImGuiViewport::Flags, giving indications to the platform backends.
ViewportFlags :: bit_set[ViewportFlag; c.int]
ViewportFlag :: enum c.int {
	IsPlatformWindow    = 0,  // Represent a Platform Window
	IsPlatformMonitor   = 1,  // Represent a Platform Monitor (unused yet)
	OwnedByApp          = 2,  // Platform Window: Is created/managed by the user application? (rather than our backend)
	NoDecoration        = 3,  // Platform Window: Disable platform decorations: title bar, borders, etc. (generally set all windows, but if ImGuiConfigFlags_ViewportsDecoration is set we only set this on popups/tooltips)
	NoTaskBarIcon       = 4,  // Platform Window: Disable platform task bar icon (generally set on popups/tooltips, or all windows if ImGuiConfigFlags_ViewportsNoTaskBarIcon is set)
	NoFocusOnAppearing  = 5,  // Platform Window: Don't take focus when created.
	NoFocusOnClick      = 6,  // Platform Window: Don't take focus when clicked on.
	NoInputs            = 7,  // Platform Window: Make mouse pass through so we can drag this window while peaking behind it.
	NoRendererClear     = 8,  // Platform Window: Renderer doesn't need to clear the framebuffer ahead (because we will fill it entirely).
	NoAutoMerge         = 9,  // Platform Window: Avoid merging this window into another host window. This can only be set via ImGuiWindowClass viewport flags override (because we need to now ahead if we are going to create a viewport in the first place!).
	TopMost             = 10, // Platform Window: Display on top (for tooltips only).
	CanHostOtherWindows = 11, // Viewport can host multiple imgui windows (secondary viewports are associated to a single window). // FIXME: In practice there's still probably code making the assumption that this is always and only on the MainViewport. Will fix once we add support for "no main viewport".
	// Output status flags (from Platform)
	IsMinimized = 12, // Platform Window: Window is minimized, can skip render. When minimized we tend to avoid using the viewport pos/size for clipping window or testing if they are contained in the viewport.
	IsFocused   = 13, // Platform Window: Window is focused (last call to Platform_GetWindowFocus() returned true)
}



////////////////////////////////////////////////////////////
// STRUCTS
////////////////////////////////////////////////////////////

Vec2 :: [2]f32
Vec4 :: [4]f32
// Sorting specifications for a table (often handling sort specs for a single column, occasionally more)
// Obtained by calling TableGetSortSpecs().
// When 'SpecsDirty == true' you can sort your data. It will be true with sorting specs have changed since last call, or the first time.
// Make sure to set 'SpecsDirty = false' after sorting, else you may wastefully sort your data every frame!
TableSortSpecs :: struct {
	Specs:      ^TableColumnSortSpecs, // Pointer to sort spec array.
	SpecsCount: c.int,                 // Sort spec count. Most often 1. May be > 1 when ImGuiTableFlags_SortMulti is enabled. May be == 0 when ImGuiTableFlags_SortTristate is enabled.
	SpecsDirty: bool,                  // Set to true when specs have changed since last time! Use this to sort again, then clear the flag.
}

// Sorting specification for one column of a table (sizeof == 12 bytes)
TableColumnSortSpecs :: struct {
	ColumnUserID:  ID,            // User id of the column (if specified by a TableSetupColumn() call)
	ColumnIndex:   i16,           // Index of the column
	SortOrder:     i16,           // Index within parent ImGuiTableSortSpecs (always stored in order starting from 0, tables sorted on a single criteria will always have a 0 here)
	SortDirection: SortDirection, // ImGuiSortDirection_Ascending or ImGuiSortDirection_Descending
}

Vector_Wchar :: struct { // Instantiation of ImVector<ImWchar>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^Wchar,
}

Vector_TextFilter_ImGuiTextRange :: struct { // Instantiation of ImVector<ImGuiTextFilter_ImGuiTextRange>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TextFilter_ImGuiTextRange,
}

Vector_char :: struct { // Instantiation of ImVector<char>
	Size:     c.int,
	Capacity: c.int,
	Data:     cstring,
}

Vector_StoragePair :: struct { // Instantiation of ImVector<ImGuiStoragePair>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^StoragePair,
}

Vector_SelectionRequest :: struct { // Instantiation of ImVector<ImGuiSelectionRequest>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^SelectionRequest,
}

Vector_DrawCmd :: struct { // Instantiation of ImVector<ImDrawCmd>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^DrawCmd,
}

Vector_DrawIdx :: struct { // Instantiation of ImVector<ImDrawIdx>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^DrawIdx,
}

Vector_DrawChannel :: struct { // Instantiation of ImVector<ImDrawChannel>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^DrawChannel,
}

Vector_DrawVert :: struct { // Instantiation of ImVector<ImDrawVert>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^DrawVert,
}

Vector_Vec2 :: struct { // Instantiation of ImVector<ImVec2>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^Vec2,
}

Vector_Vec4 :: struct { // Instantiation of ImVector<ImVec4>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^Vec4,
}

Vector_TextureID :: struct { // Instantiation of ImVector<ImTextureID>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^TextureID,
}

Vector_U8 :: struct { // Instantiation of ImVector<ImU8>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^u8,
}

Vector_DrawListPtr :: struct { // Instantiation of ImVector<ImDrawList*>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^^DrawList,
}

Vector_U32 :: struct { // Instantiation of ImVector<ImU32>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^u32,
}

Vector_FontPtr :: struct { // Instantiation of ImVector<ImFont*>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^^Font,
}

Vector_FontAtlasCustomRect :: struct { // Instantiation of ImVector<ImFontAtlasCustomRect>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^FontAtlasCustomRect,
}

Vector_FontConfig :: struct { // Instantiation of ImVector<ImFontConfig>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^FontConfig,
}

Vector_float :: struct { // Instantiation of ImVector<float>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^f32,
}

Vector_FontGlyph :: struct { // Instantiation of ImVector<ImFontGlyph>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^FontGlyph,
}

Vector_PlatformMonitor :: struct { // Instantiation of ImVector<ImGuiPlatformMonitor>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^PlatformMonitor,
}

Vector_ViewportPtr :: struct { // Instantiation of ImVector<ImGuiViewport*>
	Size:     c.int,
	Capacity: c.int,
	Data:     ^^Viewport,
}

Style :: struct {
	Alpha:                       f32,             // Global alpha applies to everything in Dear ImGui.
	DisabledAlpha:               f32,             // Additional alpha multiplier applied by BeginDisabled(). Multiply over current value of Alpha.
	WindowPadding:               Vec2,            // Padding within a window.
	WindowRounding:              f32,             // Radius of window corners rounding. Set to 0.0f to have rectangular windows. Large values tend to lead to variety of artifacts and are not recommended.
	WindowBorderSize:            f32,             // Thickness of border around windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	WindowMinSize:               Vec2,            // Minimum window size. This is a global setting. If you want to constrain individual windows, use SetNextWindowSizeConstraints().
	WindowTitleAlign:            Vec2,            // Alignment for title bar text. Defaults to (0.0f,0.5f) for left-aligned,vertically centered.
	WindowMenuButtonPosition:    Dir,             // Side of the collapsing/docking button in the title bar (None/Left/Right). Defaults to ImGuiDir_Left.
	ChildRounding:               f32,             // Radius of child window corners rounding. Set to 0.0f to have rectangular windows.
	ChildBorderSize:             f32,             // Thickness of border around child windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	PopupRounding:               f32,             // Radius of popup window corners rounding. (Note that tooltip windows use WindowRounding)
	PopupBorderSize:             f32,             // Thickness of border around popup/tooltip windows. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	FramePadding:                Vec2,            // Padding within a framed rectangle (used by most widgets).
	FrameRounding:               f32,             // Radius of frame corners rounding. Set to 0.0f to have rectangular frame (used by most widgets).
	FrameBorderSize:             f32,             // Thickness of border around frames. Generally set to 0.0f or 1.0f. (Other values are not well tested and more CPU/GPU costly).
	ItemSpacing:                 Vec2,            // Horizontal and vertical spacing between widgets/lines.
	ItemInnerSpacing:            Vec2,            // Horizontal and vertical spacing between within elements of a composed widget (e.g. a slider and its label).
	CellPadding:                 Vec2,            // Padding within a table cell. Cellpadding.x is locked for entire table. CellPadding.y may be altered between different rows.
	TouchExtraPadding:           Vec2,            // Expand reactive bounding box for touch-based system where touch position is not accurate enough. Unfortunately we don't sort widgets so priority on overlap will always be given to the first widget. So don't grow this too much!
	IndentSpacing:               f32,             // Horizontal indentation when e.g. entering a tree node. Generally == (FontSize + FramePadding.x*2).
	ColumnsMinSpacing:           f32,             // Minimum horizontal spacing between two columns. Preferably > (FramePadding.x + 1).
	ScrollbarSize:               f32,             // Width of the vertical scrollbar, Height of the horizontal scrollbar.
	ScrollbarRounding:           f32,             // Radius of grab corners for scrollbar.
	GrabMinSize:                 f32,             // Minimum width/height of a grab box for slider/scrollbar.
	GrabRounding:                f32,             // Radius of grabs corners rounding. Set to 0.0f to have rectangular slider grabs.
	LogSliderDeadzone:           f32,             // The size in pixels of the dead-zone around zero on logarithmic sliders that cross zero.
	TabRounding:                 f32,             // Radius of upper corners of a tab. Set to 0.0f to have rectangular tabs.
	TabBorderSize:               f32,             // Thickness of border around tabs.
	TabMinWidthForCloseButton:   f32,             // Minimum width for close button to appear on an unselected tab when hovered. Set to 0.0f to always show when hovering, set to FLT_MAX to never show close button unless selected.
	TabBarBorderSize:            f32,             // Thickness of tab-bar separator, which takes on the tab active color to denote focus.
	TabBarOverlineSize:          f32,             // Thickness of tab-bar overline, which highlights the selected tab-bar.
	TableAngledHeadersAngle:     f32,             // Angle of angled headers (supported values range from -50.0f degrees to +50.0f degrees).
	TableAngledHeadersTextAlign: Vec2,            // Alignment of angled headers within the cell
	ColorButtonPosition:         Dir,             // Side of the color button in the ColorEdit4 widget (left/right). Defaults to ImGuiDir_Right.
	ButtonTextAlign:             Vec2,            // Alignment of button text when button is larger than text. Defaults to (0.5f, 0.5f) (centered).
	SelectableTextAlign:         Vec2,            // Alignment of selectable text. Defaults to (0.0f, 0.0f) (top-left aligned). It's generally important to keep this left-aligned if you want to lay multiple items on a same line.
	SeparatorTextBorderSize:     f32,             // Thickness of border in SeparatorText()
	SeparatorTextAlign:          Vec2,            // Alignment of text within the separator. Defaults to (0.0f, 0.5f) (left aligned, center).
	SeparatorTextPadding:        Vec2,            // Horizontal offset of text from each edge of the separator + spacing on other axis. Generally small values. .y is recommended to be == FramePadding.y.
	DisplayWindowPadding:        Vec2,            // Apply to regular windows: amount which we enforce to keep visible when moving near edges of your screen.
	DisplaySafeAreaPadding:      Vec2,            // Apply to every windows, menus, popups, tooltips: amount where we avoid displaying contents. Adjust if you cannot see the edges of your screen (e.g. on a TV where scaling has not been configured).
	DockingSeparatorSize:        f32,             // Thickness of resizing border between docked windows
	MouseCursorScale:            f32,             // Scale software rendered mouse cursor (when io.MouseDrawCursor is enabled). We apply per-monitor DPI scaling over this scale. May be removed later.
	AntiAliasedLines:            bool,            // Enable anti-aliased lines/borders. Disable if you are really tight on CPU/GPU. Latched at the beginning of the frame (copied to ImDrawList).
	AntiAliasedLinesUseTex:      bool,            // Enable anti-aliased lines/borders using textures where possible. Require backend to render with bilinear filtering (NOT point/nearest filtering). Latched at the beginning of the frame (copied to ImDrawList).
	AntiAliasedFill:             bool,            // Enable anti-aliased edges around filled shapes (rounded rectangles, circles, etc.). Disable if you are really tight on CPU/GPU. Latched at the beginning of the frame (copied to ImDrawList).
	CurveTessellationTol:        f32,             // Tessellation tolerance when using PathBezierCurveTo() without a specific number of segments. Decrease for highly tessellated curves (higher quality, more polygons), increase to reduce quality.
	CircleTessellationMaxError:  f32,             // Maximum error (in pixels) allowed when using AddCircle()/AddCircleFilled() or drawing rounded corner rectangles with no explicit segment count specified. Decrease for higher quality but more geometry.
	Colors:                      [Col.COUNT]Vec4,
	// Behaviors
	// (It is possible to modify those fields mid-frame if specific behavior need it, unlike e.g. configuration fields in ImGuiIO)
	HoverStationaryDelay:      f32,          // Delay for IsItemHovered(ImGuiHoveredFlags_Stationary). Time required to consider mouse stationary.
	HoverDelayShort:           f32,          // Delay for IsItemHovered(ImGuiHoveredFlags_DelayShort). Usually used along with HoverStationaryDelay.
	HoverDelayNormal:          f32,          // Delay for IsItemHovered(ImGuiHoveredFlags_DelayNormal). "
	HoverFlagsForTooltipMouse: HoveredFlags, // Default flags when using IsItemHovered(ImGuiHoveredFlags_ForTooltip) or BeginItemTooltip()/SetItemTooltip() while using mouse.
	HoverFlagsForTooltipNav:   HoveredFlags, // Default flags when using IsItemHovered(ImGuiHoveredFlags_ForTooltip) or BeginItemTooltip()/SetItemTooltip() while using keyboard/gamepad.
}

// [Internal] Storage used by IsKeyDown(), IsKeyPressed() etc functions.
// If prior to 1.87 you used io.KeysDownDuration[] (which was marked as internal), you should use GetKeyData(key)->DownDuration and *NOT* io.KeysData[key]->DownDuration.
KeyData :: struct {
	Down:             bool, // True for if key is down
	DownDuration:     f32,  // Duration the key has been down (<0.0f: not pressed, 0.0f: just pressed, >0.0f: time held)
	DownDurationPrev: f32,  // Last frame duration the key has been down
	AnalogValue:      f32,  // 0.0f..1.0f for gamepad values
}

IO :: struct {
	ConfigFlags:   ConfigFlags,  // = 0              // See ImGuiConfigFlags_ enum. Set by user/application. Keyboard/Gamepad navigation options, etc.
	BackendFlags:  BackendFlags, // = 0              // See ImGuiBackendFlags_ enum. Set by backend (imgui_impl_xxx files or custom backend) to communicate features supported by the backend.
	DisplaySize:   Vec2,         // <unset>          // Main display size, in pixels (generally == GetMainViewport()->Size). May change every frame.
	DeltaTime:     f32,          // = 1.0f/60.0f     // Time elapsed since last frame, in seconds. May change every frame.
	IniSavingRate: f32,          // = 5.0f           // Minimum time between saving positions/sizes to .ini file, in seconds.
	IniFilename:   cstring,      // = "imgui.ini"    // Path to .ini file (important: default "imgui.ini" is relative to current working dir!). Set NULL to disable automatic .ini loading/saving or if you want to manually call LoadIniSettingsXXX() / SaveIniSettingsXXX() functions.
	LogFilename:   cstring,      // = "imgui_log.txt"// Path to .log file (default parameter to ImGui::LogToFile when no file is specified).
	UserData:      rawptr,       // = NULL           // Store your own data.
	// Font system
	Fonts:                   ^FontAtlas, // <auto>           // Font atlas: load, rasterize and pack one or more fonts into a single texture.
	FontGlobalScale:         f32,        // = 1.0f           // Global scale all fonts
	FontAllowUserScaling:    bool,       // = false          // [OBSOLETE] Allow user scaling text of individual window with CTRL+Wheel.
	FontDefault:             ^Font,      // = NULL           // Font to use on NewFrame(). Use NULL to uses Fonts->Fonts[0].
	DisplayFramebufferScale: Vec2,       // = (1, 1)         // For retina display or other situations where window coordinates are different from framebuffer coordinates. This generally ends up in ImDrawData::FramebufferScale.
	// Keyboard/Gamepad Navigation options
	ConfigNavSwapGamepadButtons:     bool, // = false          // Swap Activate<>Cancel (A<>B) buttons, matching typical "Nintendo/Japanese style" gamepad layout.
	ConfigNavMoveSetMousePos:        bool, // = false          // Directional/tabbing navigation teleports the mouse cursor. May be useful on TV/console systems where moving a virtual mouse is difficult. Will update io.MousePos and set io.WantSetMousePos=true.
	ConfigNavCaptureKeyboard:        bool, // = true           // Sets io.WantCaptureKeyboard when io.NavActive is set.
	ConfigNavEscapeClearFocusItem:   bool, // = true           // Pressing Escape can clear focused item + navigation id/highlight. Set to false if you want to always keep highlight on.
	ConfigNavEscapeClearFocusWindow: bool, // = false          // Pressing Escape can clear focused window as well (super set of io.ConfigNavEscapeClearFocusItem).
	ConfigNavCursorVisibleAuto:      bool, // = true           // Using directional navigation key makes the cursor visible. Mouse click hides the cursor.
	ConfigNavCursorVisibleAlways:    bool, // = false          // Navigation cursor is always visible.
	// Docking options (when ImGuiConfigFlags_DockingEnable is set)
	ConfigDockingNoSplit:            bool, // = false          // Simplified docking mode: disable window splitting, so docking is limited to merging multiple windows together into tab-bars.
	ConfigDockingWithShift:          bool, // = false          // Enable docking with holding Shift key (reduce visual noise, allows dropping in wider space)
	ConfigDockingAlwaysTabBar:       bool, // = false          // [BETA] [FIXME: This currently creates regression with auto-sizing and general overhead] Make every single floating window display within a docking node.
	ConfigDockingTransparentPayload: bool, // = false          // [BETA] Make window or viewport transparent when docking and only display docking boxes on the target viewport. Useful if rendering of multiple viewport cannot be synced. Best used with ConfigViewportsNoAutoMerge.
	// Viewport options (when ImGuiConfigFlags_ViewportsEnable is set)
	ConfigViewportsNoAutoMerge:     bool, // = false;         // Set to make all floating imgui windows always create their own viewport. Otherwise, they are merged into the main host viewports when overlapping it. May also set ImGuiViewportFlags_NoAutoMerge on individual viewport.
	ConfigViewportsNoTaskBarIcon:   bool, // = false          // Disable default OS task bar icon flag for secondary viewports. When a viewport doesn't want a task bar icon, ImGuiViewportFlags_NoTaskBarIcon will be set on it.
	ConfigViewportsNoDecoration:    bool, // = true           // Disable default OS window decoration flag for secondary viewports. When a viewport doesn't want window decorations, ImGuiViewportFlags_NoDecoration will be set on it. Enabling decoration can create subsequent issues at OS levels (e.g. minimum window size).
	ConfigViewportsNoDefaultParent: bool, // = false          // Disable default OS parenting to main viewport for secondary viewports. By default, viewports are marked with ParentViewportId = <main_viewport>, expecting the platform backend to setup a parent/child relationship between the OS windows (some backend may ignore this). Set to true if you want the default to be 0, then all viewports will be top-level OS windows.
	// Miscellaneous options
	// (you can visualize and interact with all options in 'Demo->Configuration')
	MouseDrawCursor:                    bool, // = false          // Request ImGui to draw a mouse cursor for you (if you are on a platform without a mouse cursor). Cannot be easily renamed to 'io.ConfigXXX' because this is frequently used by backend implementations.
	ConfigMacOSXBehaviors:              bool, // = defined(__APPLE__) // Swap Cmd<>Ctrl keys + OS X style text editing cursor movement using Alt instead of Ctrl, Shortcuts using Cmd/Super instead of Ctrl, Line/Text Start and End using Cmd+Arrows instead of Home/End, Double click selects by word instead of selecting whole text, Multi-selection in lists uses Cmd/Super instead of Ctrl.
	ConfigInputTrickleEventQueue:       bool, // = true           // Enable input queue trickling: some types of events submitted during the same frame (e.g. button down + up) will be spread over multiple frames, improving interactions with low framerates.
	ConfigInputTextCursorBlink:         bool, // = true           // Enable blinking cursor (optional as some users consider it to be distracting).
	ConfigInputTextEnterKeepActive:     bool, // = false          // [BETA] Pressing Enter will keep item active and select contents (single-line only).
	ConfigDragClickToInputText:         bool, // = false          // [BETA] Enable turning DragXXX widgets into text input with a simple mouse click-release (without moving). Not desirable on devices without a keyboard.
	ConfigWindowsResizeFromEdges:       bool, // = true           // Enable resizing of windows from their edges and from the lower-left corner. This requires ImGuiBackendFlags_HasMouseCursors for better mouse cursor feedback. (This used to be a per-window ImGuiWindowFlags_ResizeFromAnySide flag)
	ConfigWindowsMoveFromTitleBarOnly:  bool, // = false      // Enable allowing to move windows only when clicking on their title bar. Does not apply to windows without a title bar.
	ConfigWindowsCopyContentsWithCtrlC: bool, // = false      // [EXPERIMENTAL] CTRL+C copy the contents of focused window into the clipboard. Experimental because: (1) has known issues with nested Begin/End pairs (2) text output quality varies (3) text output is in submission order rather than spatial order.
	ConfigScrollbarScrollByPage:        bool, // = true           // Enable scrolling page by page when clicking outside the scrollbar grab. When disabled, always scroll to clicked location. When enabled, Shift+Click scrolls to clicked location.
	ConfigMemoryCompactTimer:           f32,  // = 60.0f          // Timer (in seconds) to free transient windows/tables memory buffers when unused. Set to -1.0f to disable.
	// Inputs Behaviors
	// (other variables, ones which are expected to be tweaked within UI code, are exposed in ImGuiStyle)
	MouseDoubleClickTime:    f32, // = 0.30f          // Time for a double-click, in seconds.
	MouseDoubleClickMaxDist: f32, // = 6.0f           // Distance threshold to stay in to validate a double-click, in pixels.
	MouseDragThreshold:      f32, // = 6.0f           // Distance threshold before considering we are dragging.
	KeyRepeatDelay:          f32, // = 0.275f         // When holding a key/button, time before it starts repeating, in seconds (for buttons in Repeat mode, etc.).
	KeyRepeatRate:           f32, // = 0.050f         // When holding a key/button, rate at which it repeats, in seconds.
	// Options to configure Error Handling and how we handle recoverable errors [EXPERIMENTAL]
	// - Error recovery is provided as a way to facilitate:
	//    - Recovery after a programming error (native code or scripting language - the later tends to facilitate iterating on code while running).
	//    - Recovery after running an exception handler or any error processing which may skip code after an error has been detected.
	// - Error recovery is not perfect nor guaranteed! It is a feature to ease development.
	//   You not are not supposed to rely on it in the course of a normal application run.
	// - Functions that support error recovery are using IM_ASSERT_USER_ERROR() instead of IM_ASSERT().
	// - By design, we do NOT allow error recovery to be 100% silent. One of the three options needs to be checked!
	// - Always ensure that on programmers seats you have at minimum Asserts or Tooltips enabled when making direct imgui API calls!
	//   Otherwise it would severely hinder your ability to catch and correct mistakes!
	// Read https://github.com/ocornut/imgui/wiki/Error-Handling for details.
	// - Programmer seats: keep asserts (default), or disable asserts and keep error tooltips (new and nice!)
	// - Non-programmer seats: maybe disable asserts, but make sure errors are resurfaced (tooltips, visible log entries, use callback etc.)
	// - Recovery after error/exception: record stack sizes with ErrorRecoveryStoreState(), disable assert, set log callback (to e.g. trigger high-level breakpoint), recover with ErrorRecoveryTryToRecoverState(), restore settings.
	ConfigErrorRecovery:               bool, // = true       // Enable error recovery support. Some errors won't be detected and lead to direct crashes if recovery is disabled.
	ConfigErrorRecoveryEnableAssert:   bool, // = true       // Enable asserts on recoverable error. By default call IM_ASSERT() when returning from a failing IM_ASSERT_USER_ERROR()
	ConfigErrorRecoveryEnableDebugLog: bool, // = true       // Enable debug log output on recoverable errors.
	ConfigErrorRecoveryEnableTooltip:  bool, // = true       // Enable tooltip on recoverable errors. The tooltip include a way to enable asserts if they were disabled.
	// Option to enable various debug tools showing buttons that will call the IM_DEBUG_BREAK() macro.
	// - The Item Picker tool will be available regardless of this being enabled, in order to maximize its discoverability.
	// - Requires a debugger being attached, otherwise IM_DEBUG_BREAK() options will appear to crash your application.
	//   e.g. io.ConfigDebugIsDebuggerPresent = ::IsDebuggerPresent() on Win32, or refer to ImOsIsDebuggerPresent() imgui_test_engine/imgui_te_utils.cpp for a Unix compatible version).
	ConfigDebugIsDebuggerPresent: bool, // = false          // Enable various tools calling IM_DEBUG_BREAK().
	// Tools to detect code submitting items with conflicting/duplicate IDs
	// - Code should use PushID()/PopID() in loops, or append "##xx" to same-label identifiers.
	// - Empty label e.g. Button("") == same ID as parent widget/node. Use Button("##xx") instead!
	// - See FAQ https://github.com/ocornut/imgui/blob/master/docs/FAQ.md#q-about-the-id-stack-system
	ConfigDebugHighlightIdConflicts: bool, // = true           // Highlight and show an error message when multiple items have conflicting identifiers.
	// Tools to test correct Begin/End and BeginChild/EndChild behaviors.
	// - Presently Begin()/End() and BeginChild()/EndChild() needs to ALWAYS be called in tandem, regardless of return value of BeginXXX()
	// - This is inconsistent with other BeginXXX functions and create confusion for many users.
	// - We expect to update the API eventually. In the meanwhile we provide tools to facilitate checking user-code behavior.
	ConfigDebugBeginReturnValueOnce: bool, // = false          // First-time calls to Begin()/BeginChild() will return false. NEEDS TO BE SET AT APPLICATION BOOT TIME if you don't want to miss windows.
	ConfigDebugBeginReturnValueLoop: bool, // = false          // Some calls to Begin()/BeginChild() will return false. Will cycle through window depths then repeat. Suggested use: add "io.ConfigDebugBeginReturnValue = io.KeyShift" in your main loop then occasionally press SHIFT. Windows should be flickering while running.
	// Option to deactivate io.AddFocusEvent(false) handling.
	// - May facilitate interactions with a debugger when focus loss leads to clearing inputs data.
	// - Backends may have other side-effects on focus loss, so this will reduce side-effects but not necessary remove all of them.
	ConfigDebugIgnoreFocusLoss: bool, // = false          // Ignore io.AddFocusEvent(false), consequently not calling io.ClearInputKeys()/io.ClearInputMouse() in input processing.
	// Option to audit .ini data
	ConfigDebugIniSettings: bool, // = false          // Save .ini data with extra comments (particularly helpful for Docking, but makes saving slower)
	// Nowadays those would be stored in ImGuiPlatformIO but we are leaving them here for legacy reasons.
	// Optional: Platform/Renderer backend name (informational only! will be displayed in About Window) + User data for backend/wrappers to store their own stuff.
	BackendPlatformName:     cstring,  // = NULL
	BackendRendererName:     cstring,  // = NULL
	BackendPlatformUserData: rawptr,   // = NULL           // User data for platform backend
	BackendRendererUserData: rawptr,   // = NULL           // User data for renderer backend
	BackendLanguageUserData: rawptr,   // = NULL           // User data for non C++ programming language backend
	WantCaptureMouse:        bool,     // Set when Dear ImGui will use mouse inputs, in this case do not dispatch them to your main game/application (either way, always pass on mouse inputs to imgui). (e.g. unclicked mouse is hovering over an imgui window, widget is active, mouse was clicked over an imgui window, etc.).
	WantCaptureKeyboard:     bool,     // Set when Dear ImGui will use keyboard inputs, in this case do not dispatch them to your main game/application (either way, always pass keyboard inputs to imgui). (e.g. InputText active, or an imgui window is focused and navigation is enabled, etc.).
	WantTextInput:           bool,     // Mobile/console: when set, you may display an on-screen keyboard. This is set by Dear ImGui when it wants textual keyboard input to happen (e.g. when a InputText widget is active).
	WantSetMousePos:         bool,     // MousePos has been altered, backend should reposition mouse on next frame. Rarely used! Set only when io.ConfigNavMoveSetMousePos is enabled.
	WantSaveIniSettings:     bool,     // When manual .ini load/save is active (io.IniFilename == NULL), this will be set to notify your application that you can call SaveIniSettingsToMemory() and save yourself. Important: clear io.WantSaveIniSettings yourself after saving!
	NavActive:               bool,     // Keyboard/Gamepad navigation is currently allowed (will handle ImGuiKey_NavXXX events) = a window is focused and it doesn't use the ImGuiWindowFlags_NoNavInputs flag.
	NavVisible:              bool,     // Keyboard/Gamepad navigation highlight is visible and allowed (will handle ImGuiKey_NavXXX events).
	Framerate:               f32,      // Estimate of application framerate (rolling average over 60 frames, based on io.DeltaTime), in frame per second. Solely for convenience. Slow applications may not want to use a moving average or may want to reset underlying buffers occasionally.
	MetricsRenderVertices:   c.int,    // Vertices output during last call to Render()
	MetricsRenderIndices:    c.int,    // Indices output during last call to Render() = number of triangles * 3
	MetricsRenderWindows:    c.int,    // Number of visible windows
	MetricsActiveWindows:    c.int,    // Number of active windows
	MouseDelta:              Vec2,     // Mouse delta. Note that this is zero if either current or previous position are invalid (-FLT_MAX,-FLT_MAX), so a disappearing/reappearing mouse won't have a huge delta.
	Ctx:                     ^Context, // Parent UI context (needs to be set explicitly by parent).
	// Main Input State
	// (this block used to be written by backend, since 1.87 it is best to NOT write to those directly, call the AddXXX functions above instead)
	// (reading from those variables is fair game, as they are extremely unlikely to be moving anywhere)
	MousePos:             Vec2,        // Mouse position, in pixels. Set to ImVec2(-FLT_MAX, -FLT_MAX) if mouse is unavailable (on another screen, etc.)
	MouseDown:            [5]bool,     // Mouse buttons: 0=left, 1=right, 2=middle + extras (ImGuiMouseButton_COUNT == 5). Dear ImGui mostly uses left and right buttons. Other buttons allow us to track if the mouse is being used by your application + available to user as a convenience via IsMouse** API.
	MouseWheel:           f32,         // Mouse wheel Vertical: 1 unit scrolls about 5 lines text. >0 scrolls Up, <0 scrolls Down. Hold SHIFT to turn vertical scroll into horizontal scroll.
	MouseWheelH:          f32,         // Mouse wheel Horizontal. >0 scrolls Left, <0 scrolls Right. Most users don't have a mouse with a horizontal wheel, may not be filled by all backends.
	MouseSource:          MouseSource, // Mouse actual input peripheral (Mouse/TouchScreen/Pen).
	MouseHoveredViewport: ID,          // (Optional) Modify using io.AddMouseViewportEvent(). With multi-viewports: viewport the OS mouse is hovering. If possible _IGNORING_ viewports with the ImGuiViewportFlags_NoInputs flag is much better (few backends can handle that). Set io.BackendFlags |= ImGuiBackendFlags_HasMouseHoveredViewport if you can provide this info. If you don't imgui will infer the value using the rectangles and last focused time of the viewports it knows about (ignoring other OS windows).
	KeyCtrl:              bool,        // Keyboard modifier down: Control
	KeyShift:             bool,        // Keyboard modifier down: Shift
	KeyAlt:               bool,        // Keyboard modifier down: Alt
	KeySuper:             bool,        // Keyboard modifier down: Cmd/Super/Windows
	// Other state maintained from data above + IO function calls
	KeyMods:                          KeyChord,                    // Key mods flags (any of ImGuiMod_Ctrl/ImGuiMod_Shift/ImGuiMod_Alt/ImGuiMod_Super flags, same as io.KeyCtrl/KeyShift/KeyAlt/KeySuper but merged into flags. Read-only, updated by NewFrame()
	KeysData:                         [Key.NamedKey_COUNT]KeyData, // Key state for all known keys. Use IsKeyXXX() functions to access this.
	WantCaptureMouseUnlessPopupClose: bool,                        // Alternative to WantCaptureMouse: (WantCaptureMouse == true && WantCaptureMouseUnlessPopupClose == false) when a click over void is expected to close a popup.
	MousePosPrev:                     Vec2,                        // Previous mouse position (note that MouseDelta is not necessary == MousePos-MousePosPrev, in case either position is invalid)
	MouseClickedPos:                  [5]Vec2,                     // Position at time of clicking
	MouseClickedTime:                 [5]f64,                      // Time of last click (used to figure out double-click)
	MouseClicked:                     [5]bool,                     // Mouse button went from !Down to Down (same as MouseClickedCount[x] != 0)
	MouseDoubleClicked:               [5]bool,                     // Has mouse button been double-clicked? (same as MouseClickedCount[x] == 2)
	MouseClickedCount:                [5]u16,                      // == 0 (not clicked), == 1 (same as MouseClicked[]), == 2 (double-clicked), == 3 (triple-clicked) etc. when going from !Down to Down
	MouseClickedLastCount:            [5]u16,                      // Count successive number of clicks. Stays valid after mouse release. Reset after another click is done.
	MouseReleased:                    [5]bool,                     // Mouse button went from Down to !Down
	MouseDownOwned:                   [5]bool,                     // Track if button was clicked inside a dear imgui window or over void blocked by a popup. We don't request mouse capture from the application if click started outside ImGui bounds.
	MouseDownOwnedUnlessPopupClose:   [5]bool,                     // Track if button was clicked inside a dear imgui window.
	MouseWheelRequestAxisSwap:        bool,                        // On a non-Mac system, holding SHIFT requests WheelY to perform the equivalent of a WheelX event. On a Mac system this is already enforced by the system.
	MouseCtrlLeftAsRightClick:        bool,                        // (OSX) Set to true when the current click was a ctrl-click that spawned a simulated right click
	MouseDownDuration:                [5]f32,                      // Duration the mouse button has been down (0.0f == just clicked)
	MouseDownDurationPrev:            [5]f32,                      // Previous time the mouse button has been down
	MouseDragMaxDistanceAbs:          [5]Vec2,                     // Maximum distance, absolute, on each axis, of how much mouse has traveled from the clicking point
	MouseDragMaxDistanceSqr:          [5]f32,                      // Squared maximum distance of how much mouse has traveled from the clicking point (used for moving thresholds)
	PenPressure:                      f32,                         // Touch/Pen pressure (0.0f to 1.0f, should be >0.0f only when MouseDown[0] == true). Helper storage currently unused by Dear ImGui.
	AppFocusLost:                     bool,                        // Only modify via AddFocusEvent()
	AppAcceptingEvents:               bool,                        // Only modify via SetAppAcceptingEvents()
	InputQueueSurrogate:              Wchar16,                     // For AddInputCharacterUTF16()
	InputQueueCharacters:             Vector_Wchar,                // Queue of _characters_ input (obtained by platform backend). Fill using AddInputCharacter() helper.
}

// Shared state of InputText(), passed as an argument to your callback when a ImGuiInputTextFlags_Callback* flag is used.
// The callback function should return 0 by default.
// Callbacks (follow a flag name and see comments in ImGuiInputTextFlags_ declarations for more details)
// - ImGuiInputTextFlags_CallbackEdit:        Callback on buffer edit. Note that InputText() already returns true on edit + you can always use IsItemEdited(). The callback is useful to manipulate the underlying buffer while focus is active.
// - ImGuiInputTextFlags_CallbackAlways:      Callback on each iteration
// - ImGuiInputTextFlags_CallbackCompletion:  Callback on pressing TAB
// - ImGuiInputTextFlags_CallbackHistory:     Callback on pressing Up/Down arrows
// - ImGuiInputTextFlags_CallbackCharFilter:  Callback on character inputs to replace or discard them. Modify 'EventChar' to replace or discard, or return 1 in callback to discard.
// - ImGuiInputTextFlags_CallbackResize:      Callback on buffer capacity changes request (beyond 'buf_size' parameter value), allowing the string to grow.
InputTextCallbackData :: struct {
	Ctx:       ^Context,       // Parent UI context
	EventFlag: InputTextFlags, // One ImGuiInputTextFlags_Callback*    // Read-only
	Flags:     InputTextFlags, // What user passed to InputText()      // Read-only
	UserData:  rawptr,         // What user passed to InputText()      // Read-only
	// Arguments for the different callback events
	// - During Resize callback, Buf will be same as your input buffer.
	// - However, during Completion/History/Always callback, Buf always points to our own internal data (it is not the same as your buffer)! Changes to it will be reflected into your own buffer shortly after the callback.
	// - To modify the text buffer in a callback, prefer using the InsertChars() / DeleteChars() function. InsertChars() will take care of calling the resize callback if necessary.
	// - If you know your edits are not going to resize the underlying buffer allocation, you may modify the contents of 'Buf[]' directly. You need to update 'BufTextLen' accordingly (0 <= BufTextLen < BufSize) and set 'BufDirty'' to true so InputText can update its internal state.
	EventChar:      Wchar,   // Character input                      // Read-write   // [CharFilter] Replace character with another one, or set to zero to drop. return 1 is equivalent to setting EventChar=0;
	EventKey:       Key,     // Key pressed (Up/Down/TAB)            // Read-only    // [Completion,History]
	Buf:            cstring, // Text buffer                          // Read-write   // [Resize] Can replace pointer / [Completion,History,Always] Only write to pointed data, don't replace the actual pointer!
	BufTextLen:     c.int,   // Text length (in bytes)               // Read-write   // [Resize,Completion,History,Always] Exclude zero-terminator storage. In C land: == strlen(some_text), in C++ land: string.length()
	BufSize:        c.int,   // Buffer size (in bytes) = capacity+1  // Read-only    // [Resize,Completion,History,Always] Include zero-terminator storage. In C land == ARRAYSIZE(my_char_array), in C++ land: string.capacity()+1
	BufDirty:       bool,    // Set if you modify Buf/BufTextLen!    // Write        // [Completion,History,Always]
	CursorPos:      c.int,   //                                      // Read-write   // [Completion,History,Always]
	SelectionStart: c.int,   //                                      // Read-write   // [Completion,History,Always] == to SelectionEnd when no selection)
	SelectionEnd:   c.int,   //                                      // Read-write   // [Completion,History,Always]
}

// Resizing callback data to apply custom constraint. As enabled by SetNextWindowSizeConstraints(). Callback is called during the next Begin().
// NB: For basic min/max size constraint on each axis you don't need to use the callback! The SetNextWindowSizeConstraints() parameters are enough.
SizeCallbackData :: struct {
	UserData:    rawptr, // Read-only.   What user passed to SetNextWindowSizeConstraints(). Generally store an integer or float in here (need reinterpret_cast<>).
	Pos:         Vec2,   // Read-only.   Window position, for reference.
	CurrentSize: Vec2,   // Read-only.   Current window size.
	DesiredSize: Vec2,   // Read-write.  Desired size, based on user's mouse position. Write to this field to restrain resizing.
}

// [ALPHA] Rarely used / very advanced uses only. Use with SetNextWindowClass() and DockSpace() functions.
// Important: the content of this class is still highly WIP and likely to change and be refactored
// before we stabilize Docking features. Please be mindful if using this.
// Provide hints:
// - To the platform backend via altered viewport flags (enable/disable OS decoration, OS task bar icons, etc.)
// - To the platform backend for OS level parent/child relationships of viewport.
// - To the docking system for various options and filtering.
WindowClass :: struct {
	ClassId:                    ID,            // User data. 0 = Default class (unclassed). Windows of different classes cannot be docked with each others.
	ParentViewportId:           ID,            // Hint for the platform backend. -1: use default. 0: request platform backend to not parent the platform. != 0: request platform backend to create a parent<>child relationship between the platform windows. Not conforming backends are free to e.g. parent every viewport to the main viewport or not.
	FocusRouteParentWindowId:   ID,            // ID of parent window for shortcut focus route evaluation, e.g. Shortcut() call from Parent Window will succeed when this window is focused.
	ViewportFlagsOverrideSet:   ViewportFlags, // Viewport flags to set when a window of this class owns a viewport. This allows you to enforce OS decoration or task bar icon, override the defaults on a per-window basis.
	ViewportFlagsOverrideClear: ViewportFlags, // Viewport flags to clear when a window of this class owns a viewport. This allows you to enforce OS decoration or task bar icon, override the defaults on a per-window basis.
	TabItemFlagsOverrideSet:    TabItemFlags,  // [EXPERIMENTAL] TabItem flags to set when a window of this class gets submitted into a dock node tab bar. May use with ImGuiTabItemFlags_Leading or ImGuiTabItemFlags_Trailing.
	DockNodeFlagsOverrideSet:   DockNodeFlags, // [EXPERIMENTAL] Dock node flags to set when a window of this class is hosted by a dock node (it doesn't have to be selected!)
	DockingAlwaysTabBar:        bool,          // Set to true to enforce single floating windows of this class always having their own docking node (equivalent of setting the global io.ConfigDockingAlwaysTabBar)
	DockingAllowUnclassed:      bool,          // Set to true to allow windows of this class to be docked/merged with an unclassed window. // FIXME-DOCK: Move to DockNodeFlags override?
}

// Data payload for Drag and Drop operations: AcceptDragDropPayload(), GetDragDropPayload()
Payload :: struct {
	// Members
	Data:     rawptr, // Data (copied and owned by dear imgui)
	DataSize: c.int,  // Data size
	// [Internal]
	SourceId:       ID,         // Source item id
	SourceParentId: ID,         // Source parent id (if available)
	DataFrameCount: c.int,      // Data timestamp
	DataType:       [33]c.char, // Data type tag (short user-supplied string, 32 characters max)
	Preview:        bool,       // Set when AcceptDragDropPayload() was called and mouse has been hovering the target item (nb: handle overlapping drag targets)
	Delivery:       bool,       // Set when AcceptDragDropPayload() was called and mouse button is released over the target item.
}

// [Internal]
TextFilter_ImGuiTextRange :: struct {
	b: cstring,
	e: cstring,
}

// Helper: Parse and apply text filters. In format "aaaaa[,bbbb][,ccccc]"
TextFilter :: struct {
	InputBuf:  [256]c.char,
	Filters:   Vector_TextFilter_ImGuiTextRange,
	CountGrep: c.int,
}

// Helper: Growable text buffer for logging/accumulating text
// (this could be called 'ImGuiTextBuilder' / 'ImGuiStringBuilder')
TextBuffer :: struct {
	Buf: Vector_char,
}

// [Internal] Key+Value for ImGuiStorage
StoragePair :: struct {
	key:               ID,
	__anonymous_type0: __anonymous_type0,
}

__anonymous_type0 :: struct {
	val_i: c.int,
	val_f: f32,
	val_p: rawptr,
}

// Helper: Key->Value storage
// Typically you don't have to worry about this since a storage is held within each Window.
// We use it to e.g. store collapse state for a tree (Int 0/1)
// This is optimized for efficient lookup (dichotomy into a contiguous buffer) and rare insertion (typically tied to user interactions aka max once a frame)
// You can use it as custom user storage for temporary values. Declare your own storage if, for example:
// - You want to manipulate the open/close state of a particular sub-tree in your interface (tree node uses Int 0/1 to store their state).
// - You want to store custom debug data easily without adding or editing structures in your code (probably not efficient, but convenient)
// Types are NOT stored, so it is up to you to make sure your Key don't collide with different types.
Storage :: struct {
	// [Internal]
	Data: Vector_StoragePair,
}

// Helper: Manually clip large list of items.
// If you have lots evenly spaced items and you have random access to the list, you can perform coarse
// clipping based on visibility to only submit items that are in view.
// The clipper calculates the range of visible items and advance the cursor to compensate for the non-visible items we have skipped.
// (Dear ImGui already clip items based on their bounds but: it needs to first layout the item to do so, and generally
//  fetching/submitting your own data incurs additional cost. Coarse clipping using ImGuiListClipper allows you to easily
//  scale using lists with tens of thousands of items without a problem)
// Usage:
//   ImGuiListClipper clipper;
//   clipper.Begin(1000);         // We have 1000 elements, evenly spaced.
//   while (clipper.Step())
//       for (int i = clipper.DisplayStart; i < clipper.DisplayEnd; i++)
//           ImGui::Text("line number %d", i);
// Generally what happens is:
// - Clipper lets you process the first element (DisplayStart = 0, DisplayEnd = 1) regardless of it being visible or not.
// - User code submit that one element.
// - Clipper can measure the height of the first element
// - Clipper calculate the actual range of elements to display based on the current clipping rectangle, position the cursor before the first visible element.
// - User code submit visible elements.
// - The clipper also handles various subtleties related to keyboard/gamepad navigation, wrapping etc.
ListClipper :: struct {
	Ctx:              ^Context, // Parent UI context
	DisplayStart:     c.int,    // First item to display, updated by each call to Step()
	DisplayEnd:       c.int,    // End of items to display (exclusive)
	ItemsCount:       c.int,    // [Internal] Number of items
	ItemsHeight:      f32,      // [Internal] Height of item after a first step and item submission can calculate it
	StartPosY:        f32,      // [Internal] Cursor position at the time of Begin() or after table frozen rows are all processed
	StartSeekOffsetY: f64,      // [Internal] Account for frozen rows in a table and initial loss of precision in very large windows.
	TempData:         rawptr,   // [Internal] Internal data
}

// Helper: ImColor() implicitly converts colors to either ImU32 (packed 4x1 byte) or ImVec4 (4x1 float)
// Prefer using IM_COL32() macros if you want a guaranteed compile-time ImU32 for usage with ImDrawList API.
// **Avoid storing ImColor! Store either u32 of ImVec4. This is not a full-featured color class. MAY OBSOLETE.
// **None of the ImGui API are using ImColor directly but you can use it as a convenience to pass colors in either ImU32 or ImVec4 formats. Explicitly cast to ImU32 or ImVec4 if needed.
Color :: struct {
	Value: Vec4,
}

// Main IO structure returned by BeginMultiSelect()/EndMultiSelect().
// This mainly contains a list of selection requests.
// - Use 'Demo->Tools->Debug Log->Selection' to see requests as they happen.
// - Some fields are only useful if your list is dynamic and allows deletion (getting post-deletion focus/state right is shown in the demo)
// - Below: who reads/writes each fields? 'r'=read, 'w'=write, 'ms'=multi-select code, 'app'=application/user code.
MultiSelectIO :: struct {
	//------------------------------------------// BeginMultiSelect / EndMultiSelect
	Requests:      Vector_SelectionRequest, //  ms:w, app:r     /  ms:w  app:r   // Requests to apply to your selection data.
	RangeSrcItem:  SelectionUserData,       //  ms:w  app:r     /                // (If using clipper) Begin: Source item (often the first selected item) must never be clipped: use clipper.IncludeItemByIndex() to ensure it is submitted.
	NavIdItem:     SelectionUserData,       //  ms:w, app:r     /                // (If using deletion) Last known SetNextItemSelectionUserData() value for NavId (if part of submitted items).
	NavIdSelected: bool,                    //  ms:w, app:r     /        app:r   // (If using deletion) Last known selection state for NavId (if part of submitted items).
	RangeSrcReset: bool,                    //        app:w     /  ms:r          // (If using deletion) Set before EndMultiSelect() to reset ResetSrcItem (e.g. if deleted selection).
	ItemsCount:    c.int,                   //  ms:w, app:r     /        app:r   // 'int items_count' parameter to BeginMultiSelect() is copied here for convenience, allowing simpler calls to your ApplyRequests handler. Not used internally.
}

// Selection request item
SelectionRequest :: struct {
	//------------------------------------------// BeginMultiSelect / EndMultiSelect
	Type:           SelectionRequestType, //  ms:w, app:r     /  ms:w, app:r   // Request type. You'll most often receive 1 Clear + 1 SetRange with a single-item range.
	Selected:       bool,                 //  ms:w, app:r     /  ms:w, app:r   // Parameter for SetAll/SetRange requests (true = select, false = unselect)
	RangeDirection: i8,                   //                  /  ms:w  app:r   // Parameter for SetRange request: +1 when RangeFirstItem comes before RangeLastItem, -1 otherwise. Useful if you want to preserve selection order on a backward Shift+Click.
	RangeFirstItem: SelectionUserData,    //                  /  ms:w, app:r   // Parameter for SetRange request (this is generally == RangeSrcItem when shift selecting from top to bottom).
	RangeLastItem:  SelectionUserData,    //                  /  ms:w, app:r   // Parameter for SetRange request (this is generally == RangeSrcItem when shift selecting from bottom to top). Inclusive!
}

// Optional helper to store multi-selection state + apply multi-selection requests.
// - Used by our demos and provided as a convenience to easily implement basic multi-selection.
// - Iterate selection with 'void* it = NULL; ImGuiID id; while (selection.GetNextSelectedItem(&it, &id)) { ... }'
//   Or you can check 'if (Contains(id)) { ... }' for each possible object if their number is not too high to iterate.
// - USING THIS IS NOT MANDATORY. This is only a helper and not a required API.
// To store a multi-selection, in your application you could:
// - Use this helper as a convenience. We use our simple key->value ImGuiStorage as a std::set<ImGuiID> replacement.
// - Use your own external storage: e.g. std::set<MyObjectId>, std::vector<MyObjectId>, interval trees, intrusively stored selection etc.
// In ImGuiSelectionBasicStorage we:
// - always use indices in the multi-selection API (passed to SetNextItemSelectionUserData(), retrieved in ImGuiMultiSelectIO)
// - use the AdapterIndexToStorageId() indirection layer to abstract how persistent selection data is derived from an index.
// - use decently optimized logic to allow queries and insertion of very large selection sets.
// - do not preserve selection order.
// Many combinations are possible depending on how you prefer to store your items and how you prefer to store your selection.
// Large applications are likely to eventually want to get rid of this indirection layer and do their own thing.
// See https://github.com/ocornut/imgui/wiki/Multi-Select for details and pseudo-code using this helper.
SelectionBasicStorage :: struct {
	// Members
	Size:                    c.int,                                                     //          // Number of selected items, maintained by this helper.
	PreserveOrder:           bool,                                                      // = false  // GetNextSelectedItem() will return ordered selection (currently implemented by two additional sorts of selection. Could be improved)
	UserData:                rawptr,                                                    // = NULL   // User data for use by adapter function        // e.g. selection.UserData = (void*)my_items;
	AdapterIndexToStorageId: proc "c" (self: ^SelectionBasicStorage, idx: c.int) -> ID, // e.g. selection.AdapterIndexToStorageId = [](ImGuiSelectionBasicStorage* self, int idx) { return ((MyItems**)self->UserData)[idx]->ID; };
	_SelectionOrder:         c.int,                                                     // [Internal] Increasing counter to store selection order
	_Storage:                Storage,                                                   // [Internal] Selection set. Think of this as similar to e.g. std::set<ImGuiID>. Prefer not accessing directly: iterate with GetNextSelectedItem().
}

// Optional helper to apply multi-selection requests to existing randomly accessible storage.
// Convenient if you want to quickly wire multi-select API on e.g. an array of bool or items storing their own selection state.
SelectionExternalStorage :: struct {
	// Members
	UserData:               rawptr,                                                                 // User data for use by adapter function                                // e.g. selection.UserData = (void*)my_items;
	AdapterSetItemSelected: proc "c" (self: ^SelectionExternalStorage, idx: c.int, selected: bool), // e.g. AdapterSetItemSelected = [](ImGuiSelectionExternalStorage* self, int idx, bool selected) { ((MyItems**)self->UserData)[idx]->Selected = selected; }
}

// Typically, 1 command = 1 GPU draw call (unless command is a callback)
// - VtxOffset: When 'io.BackendFlags & ImGuiBackendFlags_RendererHasVtxOffset' is enabled,
//   this fields allow us to render meshes larger than 64K vertices while keeping 16-bit indices.
//   Backends made for <1.71. will typically ignore the VtxOffset fields.
// - The ClipRect/TextureId/VtxOffset fields must be contiguous as we memcmp() them together (this is asserted for).
DrawCmd :: struct {
	ClipRect:               Vec4,         // 4*4  // Clipping rectangle (x1, y1, x2, y2). Subtract ImDrawData->DisplayPos to get clipping rectangle in "viewport" coordinates
	TextureId:              TextureID,    // 4-8  // User-provided texture ID. Set by user in ImfontAtlas::SetTexID() for fonts or passed to Image*() functions. Ignore if never using images or multiple fonts atlas.
	VtxOffset:              c.uint,       // 4    // Start offset in vertex buffer. ImGuiBackendFlags_RendererHasVtxOffset: always 0, otherwise may be >0 to support meshes larger than 64K vertices with 16-bit indices.
	IdxOffset:              c.uint,       // 4    // Start offset in index buffer.
	ElemCount:              c.uint,       // 4    // Number of indices (multiple of 3) to be rendered as triangles. Vertices are stored in the callee ImDrawList's vtx_buffer[] array, indices in idx_buffer[].
	UserCallback:           DrawCallback, // 4-8  // If != NULL, call the function instead of rendering the vertices. clip_rect and texture_id will be set normally.
	UserCallbackData:       rawptr,       // 4-8  // Callback user data (when UserCallback != NULL). If called AddCallback() with size == 0, this is a copy of the AddCallback() argument. If called AddCallback() with size > 0, this is pointing to a buffer where data is stored.
	UserCallbackDataSize:   c.int,        // 4 // Size of callback user data when using storage, otherwise 0.
	UserCallbackDataOffset: c.int,        // 4 // [Internal] Offset of callback user data when using storage, otherwise -1.
}

DrawVert :: struct {
	pos: Vec2,
	uv:  Vec2,
	col: u32,
}

// [Internal] For use by ImDrawList
DrawCmdHeader :: struct {
	ClipRect:  Vec4,
	TextureId: TextureID,
	VtxOffset: c.uint,
}

// [Internal] For use by ImDrawListSplitter
DrawChannel :: struct {
	_CmdBuffer: Vector_DrawCmd,
	_IdxBuffer: Vector_DrawIdx,
}

// Split/Merge functions are used to split the draw list into different layers which can be drawn into out of order.
// This is used by the Columns/Tables API, so items of each column can be batched together in a same draw call.
DrawListSplitter :: struct {
	_Current:  c.int,              // Current channel number (0)
	_Count:    c.int,              // Number of active channels (1+)
	_Channels: Vector_DrawChannel, // Draw channels (not resized down so _Count might be < Channels.Size)
}

// Draw command list
// This is the low-level list of polygons that ImGui:: functions are filling. At the end of the frame,
// all command lists are passed to your ImGuiIO::RenderDrawListFn function for rendering.
// Each dear imgui window contains its own ImDrawList. You can use ImGui::GetWindowDrawList() to
// access the current window draw list and draw custom primitives.
// You can interleave normal ImGui:: calls and adding primitives to the current draw list.
// In single viewport mode, top-left is == GetMainViewport()->Pos (generally 0,0), bottom-right is == GetMainViewport()->Pos+Size (generally io.DisplaySize).
// You are totally free to apply whatever transformation matrix you want to the data (depending on the use of the transformation you may want to apply it to ClipRect as well!)
// Important: Primitives are always added to the list and not culled (culling is done at higher-level by ImGui:: functions), if you use this API a lot consider coarse culling your drawn objects.
DrawList :: struct {
	// This is what you have to render
	CmdBuffer: Vector_DrawCmd,  // Draw commands. Typically 1 command = 1 GPU draw call, unless the command is a callback.
	IdxBuffer: Vector_DrawIdx,  // Index buffer. Each command consume ImDrawCmd::ElemCount of those
	VtxBuffer: Vector_DrawVert, // Vertex buffer.
	Flags:     DrawListFlags,   // Flags, you may poke into these to adjust anti-aliasing settings per-primitive.
	// [Internal, used while building lists]
	_VtxCurrentIdx:    c.uint,              // [Internal] generally == VtxBuffer.Size unless we are past 64K vertices, in which case this gets reset to 0.
	_Data:             ^DrawListSharedData, // Pointer to shared draw data (you can use ImGui::GetDrawListSharedData() to get the one from current ImGui context)
	_VtxWritePtr:      ^DrawVert,           // [Internal] point within VtxBuffer.Data after each add command (to avoid using the ImVector<> operators too much)
	_IdxWritePtr:      ^DrawIdx,            // [Internal] point within IdxBuffer.Data after each add command (to avoid using the ImVector<> operators too much)
	_Path:             Vector_Vec2,         // [Internal] current path building
	_CmdHeader:        DrawCmdHeader,       // [Internal] template of active commands. Fields should match those of CmdBuffer.back().
	_Splitter:         DrawListSplitter,    // [Internal] for channels api (note: prefer using your own persistent instance of ImDrawListSplitter!)
	_ClipRectStack:    Vector_Vec4,         // [Internal]
	_TextureIdStack:   Vector_TextureID,    // [Internal]
	_CallbacksDataBuf: Vector_U8,           // [Internal]
	_FringeScale:      f32,                 // [Internal] anti-alias fringe is scaled by this value, this helps to keep things sharp while zooming at vertex buffer content
	_OwnerName:        cstring,             // Pointer to owner window's name for debugging
}

// All draw data to render a Dear ImGui frame
// (NB: the style and the naming convention here is a little inconsistent, we currently preserve them for backward compatibility purpose,
// as this is one of the oldest structure exposed by the library! Basically, ImDrawList == CmdList)
DrawData :: struct {
	Valid:            bool,               // Only valid after Render() is called and before the next NewFrame() is called.
	CmdListsCount:    c.int,              // Number of ImDrawList* to render
	TotalIdxCount:    c.int,              // For convenience, sum of all ImDrawList's IdxBuffer.Size
	TotalVtxCount:    c.int,              // For convenience, sum of all ImDrawList's VtxBuffer.Size
	CmdLists:         Vector_DrawListPtr, // Array of ImDrawList* to render. The ImDrawLists are owned by ImGuiContext and only pointed to from here.
	DisplayPos:       Vec2,               // Top-left position of the viewport to render (== top-left of the orthogonal projection matrix to use) (== GetMainViewport()->Pos for the main viewport, == (0.0) in most single-viewport applications)
	DisplaySize:      Vec2,               // Size of the viewport to render (== GetMainViewport()->Size for the main viewport, == io.DisplaySize in most single-viewport applications)
	FramebufferScale: Vec2,               // Amount of pixels for each unit of DisplaySize. Based on io.DisplayFramebufferScale. Generally (1,1) on normal display, (2,2) on OSX with Retina display.
	OwnerViewport:    ^Viewport,          // Viewport carrying the ImDrawData instance, might be of use to the renderer (generally not).
}

FontConfig :: struct {
	FontData:             rawptr, //          // TTF/OTF data
	FontDataSize:         c.int,  //          // TTF/OTF data size
	FontDataOwnedByAtlas: bool,   // true     // TTF/OTF data ownership taken by the container ImFontAtlas (will delete memory itself).
	FontNo:               c.int,  // 0        // Index of font within TTF/OTF file
	SizePixels:           f32,    //          // Size in pixels for rasterizer (more or less maps to the resulting font height).
	OversampleH:          c.int,  // 2        // Rasterize at higher quality for sub-pixel positioning. Note the difference between 2 and 3 is minimal. You can reduce this to 1 for large glyphs save memory. Read https://github.com/nothings/stb/blob/master/tests/oversample/README.md for details.
	OversampleV:          c.int,  // 1        // Rasterize at higher quality for sub-pixel positioning. This is not really useful as we don't use sub-pixel positions on the Y axis.
	PixelSnapH:           bool,   // false    // Align every glyph AdvanceX to pixel boundaries. Useful e.g. if you are merging a non-pixel aligned font with the default font. If enabled, you can set OversampleH/V to 1.
	GlyphExtraSpacing:    Vec2,   // 0, 0     // Extra spacing (in pixels) between glyphs when rendered: essentially add to glyph->AdvanceX. Only X axis is supported for now.
	GlyphOffset:          Vec2,   // 0, 0     // Offset all glyphs from this font input.
	GlyphRanges:          ^Wchar, // NULL     // THE ARRAY DATA NEEDS TO PERSIST AS LONG AS THE FONT IS ALIVE. Pointer to a user-provided list of Unicode range (2 value per range, values are inclusive, zero-terminated list).
	GlyphMinAdvanceX:     f32,    // 0        // Minimum AdvanceX for glyphs, set Min to align font icons, set both Min/Max to enforce mono-space font
	GlyphMaxAdvanceX:     f32,    // FLT_MAX  // Maximum AdvanceX for glyphs
	MergeMode:            bool,   // false    // Merge into previous ImFont, so you can combine multiple inputs font into one ImFont (e.g. ASCII font + icons + Japanese glyphs). You may want to use GlyphOffset.y when merge font of different heights.
	FontBuilderFlags:     c.uint, // 0        // Settings for custom font builder. THIS IS BUILDER IMPLEMENTATION DEPENDENT. Leave as zero if unsure.
	RasterizerMultiply:   f32,    // 1.0f     // Linearly brighten (>1.0f) or darken (<1.0f) font output. Brightening small fonts may be a good workaround to make them more readable. This is a silly thing we may remove in the future.
	RasterizerDensity:    f32,    // 1.0f     // DPI scale for rasterization, not altering other font metrics: make it easy to swap between e.g. a 100% and a 400% fonts for a zooming display. IMPORTANT: If you increase this it is expected that you increase font scale accordingly, otherwise quality may look lowered.
	EllipsisChar:         Wchar,  // 0        // Explicitly specify unicode codepoint of ellipsis character. When fonts are being merged first specified ellipsis will be used.
	// [Internal]
	Name:    [40]c.char, // Name (strictly to ease debugging)
	DstFont: ^Font,
}

// Hold rendering data for one glyph.
// (Note: some language parsers may fail to convert the 31+1 bitfield members, in this case maybe drop store a single u32 or we can rework this)
FontGlyph :: struct {
	Colored:   c.uint, // Flag to indicate glyph is colored and should generally ignore tinting (make it usable with no shift on little-endian as this is used in loops)
	Visible:   c.uint, // Flag to indicate glyph has no visible pixels (e.g. space). Allow early out when rendering.
	Codepoint: c.uint, // 0x0000..0x10FFFF
	AdvanceX:  f32,    // Distance to next character (= data from font + ImFontConfig::GlyphExtraSpacing.x baked in)
	X0:        f32,    // Glyph corners
	Y0:        f32,    // Glyph corners
	X1:        f32,    // Glyph corners
	Y1:        f32,    // Glyph corners
	U0:        f32,    // Texture coordinates
	V0:        f32,    // Texture coordinates
	U1:        f32,    // Texture coordinates
	V1:        f32,    // Texture coordinates
}

// Helper to build glyph ranges from text/string data. Feed your application strings/characters to it then call BuildRanges().
// This is essentially a tightly packed of vector of 64k booleans = 8KB storage.
FontGlyphRangesBuilder :: struct {
	UsedChars: Vector_U32, // Store 1-bit per Unicode code point (0=unused, 1=used)
}

// See ImFontAtlas::AddCustomRectXXX functions.
FontAtlasCustomRect :: struct {
	X: c.ushort, // Output   // Packed position in Atlas
	Y: c.ushort, // Output   // Packed position in Atlas
	// [Internal]
	Width: c.ushort, // Input    // Desired rectangle dimension
	// [Internal]
	Height:        c.ushort, // Input    // Desired rectangle dimension
	GlyphID:       c.uint,   // Input    // For custom font glyphs only (ID < 0x110000)
	GlyphColored:  c.uint,   // Input  // For custom font glyphs only: glyph is colored, removed tinting.
	GlyphAdvanceX: f32,      // Input    // For custom font glyphs only: glyph xadvance
	GlyphOffset:   Vec2,     // Input    // For custom font glyphs only: glyph display offset
	Font_:         ^Font,    // Input    // For custom font glyphs only: target font
}

// Load and rasterize multiple TTF/OTF fonts into a same texture. The font atlas will build a single texture holding:
//  - One or more fonts.
//  - Custom graphics data needed to render the shapes needed by Dear ImGui.
//  - Mouse cursor shapes for software cursor rendering (unless setting 'Flags |= ImFontAtlasFlags_NoMouseCursors' in the font atlas).
// It is the user-code responsibility to setup/build the atlas, then upload the pixel data into a texture accessible by your graphics api.
//  - Optionally, call any of the AddFont*** functions. If you don't call any, the default font embedded in the code will be loaded for you.
//  - Call GetTexDataAsAlpha8() or GetTexDataAsRGBA32() to build and retrieve pixels data.
//  - Upload the pixels data into a texture within your graphics system (see imgui_impl_xxxx.cpp examples)
//  - Call SetTexID(my_tex_id); and pass the pointer/identifier to your texture in a format natural to your graphics API.
//    This value will be passed back to you during rendering to identify the texture. Read FAQ entry about ImTextureID for more details.
// Common pitfalls:
// - If you pass a 'glyph_ranges' array to AddFont*** functions, you need to make sure that your array persist up until the
//   atlas is build (when calling GetTexData*** or Build()). We only copy the pointer, not the data.
// - Important: By default, AddFontFromMemoryTTF() takes ownership of the data. Even though we are not writing to it, we will free the pointer on destruction.
//   You can set font_cfg->FontDataOwnedByAtlas=false to keep ownership of your data and it won't be freed,
// - Even though many functions are suffixed with "TTF", OTF data is supported just as well.
// - This is an old API and it is currently awkward for those and various other reasons! We will address them in the future!
FontAtlas :: struct {
	Flags:           FontAtlasFlags, // Build flags (see ImFontAtlasFlags_)
	TexID:           TextureID,      // User data to refer to the texture once it has been uploaded to user's graphic systems. It is passed back to you during rendering via the ImDrawCmd structure.
	TexDesiredWidth: c.int,          // Texture width desired by user before Build(). Must be a power-of-two. If have many glyphs your graphics API have texture size restrictions you may want to increase texture width to decrease height.
	TexGlyphPadding: c.int,          // FIXME: Should be called "TexPackPadding". Padding between glyphs within texture in pixels. Defaults to 1. If your rendering method doesn't rely on bilinear filtering you may set this to 0 (will also need to set AntiAliasedLinesUseTex = false).
	Locked:          bool,           // Marked as Locked by ImGui::NewFrame() so attempt to modify the atlas will assert.
	UserData:        rawptr,         // Store your own atlas related user-data (if e.g. you have multiple font atlas).
	// [Internal]
	// NB: Access texture data via GetTexData*() calls! Which will setup a default font for you.
	TexReady:           bool,                       // Set when texture was built matching current font input
	TexPixelsUseColors: bool,                       // Tell whether our texture data is known to use colors (rather than just alpha channel), in order to help backend select a format.
	TexPixelsAlpha8:    ^c.uchar,                   // 1 component per pixel, each component is unsigned 8-bit. Total size = TexWidth * TexHeight
	TexPixelsRGBA32:    ^c.uint,                    // 4 component per pixel, each component is unsigned 8-bit. Total size = TexWidth * TexHeight * 4
	TexWidth:           c.int,                      // Texture width calculated during Build().
	TexHeight:          c.int,                      // Texture height calculated during Build().
	TexUvScale:         Vec2,                       // = (1.0f/TexWidth, 1.0f/TexHeight)
	TexUvWhitePixel:    Vec2,                       // Texture coordinates to a white pixel
	Fonts:              Vector_FontPtr,             // Hold all the fonts returned by AddFont*. Fonts[0] is the default font upon calling ImGui::NewFrame(), use ImGui::PushFont()/PopFont() to change the current font.
	CustomRects:        Vector_FontAtlasCustomRect, // Rectangles for packing custom texture data into the atlas.
	ConfigData:         Vector_FontConfig,          // Configuration data
	TexUvLines:         [64]Vec4,                   // UVs for baked anti-aliased lines
	// [Internal] Font builder
	FontBuilderIO:    ^FontBuilderIO, // Opaque interface to a font builder (default to stb_truetype, can be changed to use FreeType by defining IMGUI_ENABLE_FREETYPE).
	FontBuilderFlags: c.uint,         // Shared flags (for all fonts) for custom font builder. THIS IS BUILD IMPLEMENTATION DEPENDENT. Per-font override is also available in ImFontConfig.
	// [Internal] Packing data
	PackIdMouseCursors: c.int, // Custom texture rectangle ID for white pixel and mouse cursors
	PackIdLines:        c.int, // Custom texture rectangle ID for baked anti-aliased lines
}

// Font runtime data and rendering
// ImFontAtlas automatically loads a default embedded font for you when you call GetTexDataAsAlpha8() or GetTexDataAsRGBA32().
Font :: struct {
	// [Internal] Members: Hot ~20/24 bytes (for CalcTextSize)
	IndexAdvanceX:    Vector_float, // 12-16 // out //            // Sparse. Glyphs->AdvanceX in a directly indexable way (cache-friendly for CalcTextSize functions which only this info, and are often bottleneck in large UI).
	FallbackAdvanceX: f32,          // 4     // out // = FallbackGlyph->AdvanceX
	FontSize:         f32,          // 4     // in  //            // Height of characters/line, set during loading (don't change after loading)
	// [Internal] Members: Hot ~28/40 bytes (for RenderText loop)
	IndexLookup:   Vector_Wchar,     // 12-16 // out //            // Sparse. Index glyphs by Unicode code-point.
	Glyphs:        Vector_FontGlyph, // 12-16 // out //            // All glyphs.
	FallbackGlyph: ^FontGlyph,       // 4-8   // out // = FindGlyph(FontFallbackChar)
	// [Internal] Members: Cold ~32/40 bytes
	// Conceptually ConfigData[] is the list of font sources merged to create this font.
	ContainerAtlas:      ^FontAtlas,  // 4-8   // out //            // What we has been loaded into
	ConfigData:          ^FontConfig, // 4-8   // in  //            // Pointer within ContainerAtlas->ConfigData to ConfigDataCount instances
	ConfigDataCount:     c.short,     // 2     // in  // ~ 1        // Number of ImFontConfig involved in creating this font. Bigger than 1 when merging multiple font sources into one ImFont.
	EllipsisCharCount:   c.short,     // 1     // out // 1 or 3
	EllipsisChar:        Wchar,       // 2-4   // out // = '...'/'.'// Character used for ellipsis rendering.
	FallbackChar:        Wchar,       // 2-4   // out // = FFFD/'?' // Character used if a glyph isn't found.
	EllipsisWidth:       f32,         // 4     // out               // Width
	EllipsisCharStep:    f32,         // 4     // out               // Step between characters when EllipsisCount > 0
	DirtyLookupTables:   bool,        // 1     // out //
	Scale:               f32,         // 4     // in  // = 1.f      // Base font scale, multiplied by the per-window font scale which you can adjust with SetWindowFontScale()
	Ascent:              f32,         // 4+4   // out //            // Ascent: distance from top to bottom of e.g. 'A' [0..FontSize] (unscaled)
	Descent:             f32,         // 4+4   // out //            // Ascent: distance from top to bottom of e.g. 'A' [0..FontSize] (unscaled)
	MetricsTotalSurface: c.int,       // 4     // out //            // Total surface in pixels to get an idea of the font rasterization/texture cost (not exact, we approximate the cost of padding between glyphs)
	Used4kPagesMap:      [2]u8,       // 2 bytes if ImWchar=ImWchar16, 34 bytes if ImWchar==ImWchar32. Store 1-bit for each block of 4K codepoints that has one active glyph. This is mainly used to facilitate iterations across all used codepoints.
}

// - Currently represents the Platform Window created by the application which is hosting our Dear ImGui windows.
// - With multi-viewport enabled, we extend this concept to have multiple active viewports.
// - In the future we will extend this concept further to also represent Platform Monitor and support a "no main platform window" operation mode.
// - About Main Area vs Work Area:
//   - Main Area = entire viewport.
//   - Work Area = entire viewport minus sections used by main menu bars (for platform windows), or by task bar (for platform monitor).
//   - Windows are generally trying to stay within the Work Area of their host viewport.
Viewport :: struct {
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
	RendererUserData:      rawptr, // void* to hold custom data structure for the renderer (e.g. swap chain, framebuffers etc.). generally set by your Renderer_CreateWindow function.
	PlatformUserData:      rawptr, // void* to hold custom data structure for the OS / platform (e.g. windowing info, render context). generally set by your Platform_CreateWindow function.
	PlatformHandle:        rawptr, // void* to hold higher-level, platform window handle (e.g. HWND, GLFWWindow*, SDL_Window*), for FindViewportByPlatformHandle().
	PlatformHandleRaw:     rawptr, // void* to hold lower-level, platform-native window handle (under Win32 this is expected to be a HWND, unused for other platforms), when using an abstraction layer like GLFW or SDL (where PlatformHandle would be a SDL_Window*)
	PlatformWindowCreated: bool,   // Platform window has been created (Platform_CreateWindow() has been called). This is false during the first frame where a viewport is being created.
	PlatformRequestMove:   bool,   // Platform window requested move (e.g. window was moved by the OS / host window manager, authoritative position will be OS window position)
	PlatformRequestResize: bool,   // Platform window requested resize (e.g. window was resized by the OS / host window manager, authoritative size will be OS window size)
	PlatformRequestClose:  bool,   // Platform window requested closure (e.g. window was moved by the OS / host window manager, e.g. pressing ALT-F4)
}

// Access via ImGui::GetPlatformIO()
PlatformIO :: struct {
	// Optional: Access OS clipboard
	// (default to use native Win32 clipboard on Windows, otherwise uses a private clipboard. Override to access OS clipboard on other architectures)
	Platform_GetClipboardTextFn: proc "c" (ctx: ^Context) -> cstring,
	Platform_SetClipboardTextFn: proc "c" (ctx: ^Context, text: cstring),
	Platform_ClipboardUserData:  rawptr,
	// Optional: Open link/folder/file in OS Shell
	// (default to use ShellExecuteA() on Windows, system() on Linux/Mac)
	Platform_OpenInShellFn:       proc "c" (ctx: ^Context, path: cstring) -> bool,
	Platform_OpenInShellUserData: rawptr,
	// Optional: Notify OS Input Method Editor of the screen position of your cursor for text input position (e.g. when using Japanese/Chinese IME on Windows)
	// (default to use native imm32 api on Windows)
	Platform_SetImeDataFn: proc "c" (ctx: ^Context, viewport: ^Viewport, data: ^PlatformImeData),
	Platform_ImeUserData:  rawptr,
	// Optional: Platform locale
	// [Experimental] Configure decimal point e.g. '.' or ',' useful for some languages (e.g. German), generally pulled from *localeconv()->decimal_point
	Platform_LocaleDecimalPoint: Wchar, // '.'
	// Written by some backends during ImGui_ImplXXXX_RenderDrawData() call to point backend_specific ImGui_ImplXXXX_RenderState* structure.
	Renderer_RenderState: rawptr,
	// Platform Backend functions (e.g. Win32, GLFW, SDL) ------------------- Called by -----
	Platform_CreateWindow:            proc "c" (vp: ^Viewport),                                                                     // . . U . .  // Create a new platform window for the given viewport
	Platform_DestroyWindow:           proc "c" (vp: ^Viewport),                                                                     // N . U . D  //
	Platform_ShowWindow:              proc "c" (vp: ^Viewport),                                                                     // . . U . .  // Newly created windows are initially hidden so SetWindowPos/Size/Title can be called on them before showing the window
	Platform_SetWindowPos:            proc "c" (vp: ^Viewport, pos: Vec2),                                                          // . . U . .  // Set platform window position (given the upper-left corner of client area)
	Platform_GetWindowPos:            proc "c" (vp: ^Viewport) -> Vec2,                                                             // N . . . .  //
	Platform_SetWindowSize:           proc "c" (vp: ^Viewport, size: Vec2),                                                         // . . U . .  // Set platform window client area size (ignoring OS decorations such as OS title bar etc.)
	Platform_GetWindowSize:           proc "c" (vp: ^Viewport) -> Vec2,                                                             // N . . . .  // Get platform window client area size
	Platform_SetWindowFocus:          proc "c" (vp: ^Viewport),                                                                     // N . . . .  // Move window to front and set input focus
	Platform_GetWindowFocus:          proc "c" (vp: ^Viewport) -> bool,                                                             // . . U . .  //
	Platform_GetWindowMinimized:      proc "c" (vp: ^Viewport) -> bool,                                                             // N . . . .  // Get platform window minimized state. When minimized, we generally won't attempt to get/set size and contents will be culled more easily
	Platform_SetWindowTitle:          proc "c" (vp: ^Viewport, str: cstring),                                                       // . . U . .  // Set platform window title (given an UTF-8 string)
	Platform_SetWindowAlpha:          proc "c" (vp: ^Viewport, alpha: f32),                                                         // . . U . .  // (Optional) Setup global transparency (not per-pixel transparency)
	Platform_UpdateWindow:            proc "c" (vp: ^Viewport),                                                                     // . . U . .  // (Optional) Called by UpdatePlatformWindows(). Optional hook to allow the platform backend from doing general book-keeping every frame.
	Platform_RenderWindow:            proc "c" (vp: ^Viewport, render_arg: rawptr),                                                 // . . . R .  // (Optional) Main rendering (platform side! This is often unused, or just setting a "current" context for OpenGL bindings). 'render_arg' is the value passed to RenderPlatformWindowsDefault().
	Platform_SwapBuffers:             proc "c" (vp: ^Viewport, render_arg: rawptr),                                                 // . . . R .  // (Optional) Call Present/SwapBuffers (platform side! This is often unused!). 'render_arg' is the value passed to RenderPlatformWindowsDefault().
	Platform_GetWindowDpiScale:       proc "c" (vp: ^Viewport) -> f32,                                                              // N . . . .  // (Optional) [BETA] FIXME-DPI: DPI handling: Return DPI scale for this viewport. 1.0f = 96 DPI.
	Platform_OnChangedViewport:       proc "c" (vp: ^Viewport),                                                                     // . F . . .  // (Optional) [BETA] FIXME-DPI: DPI handling: Called during Begin() every time the viewport we are outputting into changes, so backend has a chance to swap fonts to adjust style.
	Platform_GetWindowWorkAreaInsets: proc "c" (vp: ^Viewport) -> Vec4,                                                             // N . . . .  // (Optional) [BETA] Get initial work area inset for the viewport (won't be covered by main menu bar, dockspace over viewport etc.). Default to (0,0),(0,0). 'safeAreaInsets' in iOS land, 'DisplayCutout' in Android land.
	Platform_CreateVkSurface:         proc "c" (vp: ^Viewport, vk_inst: u64, vk_allocators: rawptr, out_vk_surface: ^u64) -> c.int, // (Optional) For a Vulkan Renderer to call into Platform code (since the surface creation needs to tie them both).
	// Renderer Backend functions (e.g. DirectX, OpenGL, Vulkan) ------------ Called by -----
	Renderer_CreateWindow:  proc "c" (vp: ^Viewport),                     // . . U . .  // Create swap chain, frame buffers etc. (called after Platform_CreateWindow)
	Renderer_DestroyWindow: proc "c" (vp: ^Viewport),                     // N . U . D  // Destroy swap chain, frame buffers etc. (called before Platform_DestroyWindow)
	Renderer_SetWindowSize: proc "c" (vp: ^Viewport, size: Vec2),         // . . U . .  // Resize swap chain, frame buffers etc. (called after Platform_SetWindowSize)
	Renderer_RenderWindow:  proc "c" (vp: ^Viewport, render_arg: rawptr), // . . . R .  // (Optional) Clear framebuffer, setup render target, then render the viewport->DrawData. 'render_arg' is the value passed to RenderPlatformWindowsDefault().
	Renderer_SwapBuffers:   proc "c" (vp: ^Viewport, render_arg: rawptr), // . . . R .  // (Optional) Call Present/SwapBuffers. 'render_arg' is the value passed to RenderPlatformWindowsDefault().
	// (Optional) Monitor list
	// - Updated by: app/backend. Update every frame to dynamically support changing monitor or DPI configuration.
	// - Used by: dear imgui to query DPI info, clamp popups/tooltips within same monitor and not have them straddle monitors.
	Monitors: Vector_PlatformMonitor,
	// Viewports list (the list is updated by calling ImGui::EndFrame or ImGui::Render)
	// (in the future we will attempt to organize this feature to remove the need for a "main viewport")
	Viewports: Vector_ViewportPtr, // Main viewports, followed by all secondary viewports.
}

// (Optional) This is required when enabling multi-viewport. Represent the bounds of each connected monitor/display and their DPI.
// We use this information for multiple DPI support + clamping the position of popups and tooltips so they don't straddle multiple monitors.
PlatformMonitor :: struct {
	MainPos:        Vec2,   // Coordinates of the area displayed on this monitor (Min = upper left, Max = bottom right)
	MainSize:       Vec2,   // Coordinates of the area displayed on this monitor (Min = upper left, Max = bottom right)
	WorkPos:        Vec2,   // Coordinates without task bars / side bars / menu bars. Used to avoid positioning popups/tooltips inside this region. If you don't have this info, please copy the value for MainPos/MainSize.
	WorkSize:       Vec2,   // Coordinates without task bars / side bars / menu bars. Used to avoid positioning popups/tooltips inside this region. If you don't have this info, please copy the value for MainPos/MainSize.
	DpiScale:       f32,    // 1.0f = 96 DPI
	PlatformHandle: rawptr, // Backend dependant data (e.g. HMONITOR, GLFWmonitor*, SDL Display Index, NSScreen*)
}

// (Optional) Support for IME (Input Method Editor) via the platform_io.Platform_SetImeDataFn() function.
PlatformImeData :: struct {
	WantVisible:     bool, // A widget wants the IME to be visible
	InputPos:        Vec2, // Position of the input cursor
	InputLineHeight: f32,  // Line height
}


////////////////////////////////////////////////////////////
// FUNCTIONS
////////////////////////////////////////////////////////////

@(default_calling_convention="c")
foreign lib {
	// Context creation and access
	// - Each context create its own ImFontAtlas by default. You may instance one yourself and pass it to CreateContext() to share a font atlas between contexts.
	// - DLL users: heaps and globals are not shared across DLL boundaries! You will need to call SetCurrentContext() + SetAllocatorFunctions()
	//   for each static/DLL boundary you are calling from. Read "Context and Memory Allocators" section of imgui.cpp for details.
	@(link_name="ImGui_CreateContext")     CreateContext     :: proc(shared_font_atlas: ^FontAtlas = nil) -> ^Context ---
	@(link_name="ImGui_DestroyContext")    DestroyContext    :: proc(ctx: ^Context = nil)                             --- // NULL = destroy current context
	@(link_name="ImGui_GetCurrentContext") GetCurrentContext :: proc() -> ^Context                                    ---
	@(link_name="ImGui_SetCurrentContext") SetCurrentContext :: proc(ctx: ^Context)                                   ---
	// Main
	@(link_name="ImGui_GetIO")         GetIO         :: proc() -> ^IO         --- // access the ImGuiIO structure (mouse/keyboard/gamepad inputs, time, various configuration options/flags)
	@(link_name="ImGui_GetPlatformIO") GetPlatformIO :: proc() -> ^PlatformIO --- // access the ImGuiPlatformIO structure (mostly hooks/functions to connect to platform/renderer and OS Clipboard, IME etc.)
	@(link_name="ImGui_GetStyle")      GetStyle      :: proc() -> ^Style      --- // access the Style structure (colors, sizes). Always use PushStyleColor(), PushStyleVar() to modify style mid-frame!
	@(link_name="ImGui_NewFrame")      NewFrame      :: proc()                --- // start a new Dear ImGui frame, you can submit any command from this point until Render()/EndFrame().
	@(link_name="ImGui_EndFrame")      EndFrame      :: proc()                --- // ends the Dear ImGui frame. automatically called by Render(). If you don't need to render data (skipping rendering) you may call EndFrame() without Render()... but you'll have wasted CPU already! If you don't need to render, better to not create any windows and not call NewFrame() at all!
	@(link_name="ImGui_Render")        Render        :: proc()                --- // ends the Dear ImGui frame, finalize the draw data. You can then get call GetDrawData().
	@(link_name="ImGui_GetDrawData")   GetDrawData   :: proc() -> ^DrawData   --- // valid after Render() and until the next call to NewFrame(). this is what you have to render.
	// Demo, Debug, Information
	@(link_name="ImGui_ShowDemoWindow")        ShowDemoWindow        :: proc(p_open: ^bool = nil)    --- // create Demo window. demonstrate most ImGui features. call this to learn about the library! try to make it always available in your application!
	@(link_name="ImGui_ShowMetricsWindow")     ShowMetricsWindow     :: proc(p_open: ^bool = nil)    --- // create Metrics/Debugger window. display Dear ImGui internals: windows, draw commands, various internal state, etc.
	@(link_name="ImGui_ShowDebugLogWindow")    ShowDebugLogWindow    :: proc(p_open: ^bool = nil)    --- // create Debug Log window. display a simplified log of important dear imgui events.
	@(link_name="ImGui_ShowIDStackToolWindow") ShowIDStackToolWindow :: proc(p_open: ^bool = nil)    --- // create Stack Tool window. hover items with mouse to query information about the source of their unique ID.
	@(link_name="ImGui_ShowAboutWindow")       ShowAboutWindow       :: proc(p_open: ^bool = nil)    --- // create About window. display Dear ImGui version, credits and build/system information.
	@(link_name="ImGui_ShowStyleEditor")       ShowStyleEditor       :: proc(ref: ^Style = nil)      --- // add style editor block (not a window). you can pass in a reference ImGuiStyle structure to compare to, revert to and save to (else it uses the default style)
	@(link_name="ImGui_ShowStyleSelector")     ShowStyleSelector     :: proc(label: cstring) -> bool --- // add style selector block (not a window), essentially a combo listing the default styles.
	@(link_name="ImGui_ShowFontSelector")      ShowFontSelector      :: proc(label: cstring)         --- // add font selector block (not a window), essentially a combo listing the loaded fonts.
	@(link_name="ImGui_ShowUserGuide")         ShowUserGuide         :: proc()                       --- // add basic help/info block (not a window): how to manipulate ImGui as an end-user (mouse/keyboard controls).
	@(link_name="ImGui_GetVersion")            GetVersion            :: proc() -> cstring            --- // get the compiled version string e.g. "1.80 WIP" (essentially the value for IMGUI_VERSION from the compiled version of imgui.cpp)
	// Styles
	@(link_name="ImGui_StyleColorsDark")    StyleColorsDark    :: proc(dst: ^Style = nil) --- // new, recommended style (default)
	@(link_name="ImGui_StyleColorsLight")   StyleColorsLight   :: proc(dst: ^Style = nil) --- // best used with borders and a custom, thicker font
	@(link_name="ImGui_StyleColorsClassic") StyleColorsClassic :: proc(dst: ^Style = nil) --- // classic imgui style
	// Windows
	// - Begin() = push window to the stack and start appending to it. End() = pop window from the stack.
	// - Passing 'bool* p_open != NULL' shows a window-closing widget in the upper-right corner of the window,
	//   which clicking will set the boolean to false when clicked.
	// - You may append multiple times to the same window during the same frame by calling Begin()/End() pairs multiple times.
	//   Some information such as 'flags' or 'p_open' will only be considered by the first call to Begin().
	// - Begin() return false to indicate the window is collapsed or fully clipped, so you may early out and omit submitting
	//   anything to the window. Always call a matching End() for each Begin() call, regardless of its return value!
	//   [Important: due to legacy reason, Begin/End and BeginChild/EndChild are inconsistent with all other functions
	//    such as BeginMenu/EndMenu, BeginPopup/EndPopup, etc. where the EndXXX call should only be called if the corresponding
	//    BeginXXX function returned true. Begin and BeginChild are the only odd ones out. Will be fixed in a future update.]
	// - Note that the bottom of window stack always contains a window called "Debug".
	@(link_name="ImGui_Begin") Begin :: proc(name: cstring, p_open: ^bool = nil, flags: WindowFlags = {}) -> bool ---
	@(link_name="ImGui_End")   End   :: proc()                                                                    ---
	// Child Windows
	// - Use child windows to begin into a self-contained independent scrolling/clipping regions within a host window. Child windows can embed their own child.
	// - Before 1.90 (November 2023), the "ImGuiChildFlags child_flags = 0" parameter was "bool border = false".
	//   This API is backward compatible with old code, as we guarantee that ImGuiChildFlags_Borders == true.
	//   Consider updating your old code:
	//      BeginChild("Name", size, false)   -> Begin("Name", size, 0); or Begin("Name", size, ImGuiChildFlags_None);
	//      BeginChild("Name", size, true)    -> Begin("Name", size, ImGuiChildFlags_Borders);
	// - Manual sizing (each axis can use a different setting e.g. ImVec2(0.0f, 400.0f)):
	//     == 0.0f: use remaining parent window size for this axis.
	//      > 0.0f: use specified size for this axis.
	//      < 0.0f: right/bottom-align to specified distance from available content boundaries.
	// - Specifying ImGuiChildFlags_AutoResizeX or ImGuiChildFlags_AutoResizeY makes the sizing automatic based on child contents.
	//   Combining both ImGuiChildFlags_AutoResizeX _and_ ImGuiChildFlags_AutoResizeY defeats purpose of a scrolling region and is NOT recommended.
	// - BeginChild() returns false to indicate the window is collapsed or fully clipped, so you may early out and omit submitting
	//   anything to the window. Always call a matching EndChild() for each BeginChild() call, regardless of its return value.
	//   [Important: due to legacy reason, Begin/End and BeginChild/EndChild are inconsistent with all other functions
	//    such as BeginMenu/EndMenu, BeginPopup/EndPopup, etc. where the EndXXX call should only be called if the corresponding
	//    BeginXXX function returned true. Begin and BeginChild are the only odd ones out. Will be fixed in a future update.]
	@(link_name="ImGui_BeginChild")   BeginChild   :: proc(str_id: cstring, size: Vec2 = {0, 0}, child_flags: ChildFlags = {}, window_flags: WindowFlags = {}) -> bool ---
	@(link_name="ImGui_BeginChildID") BeginChildID :: proc(id: ID, size: Vec2 = {0, 0}, child_flags: ChildFlags = {}, window_flags: WindowFlags = {}) -> bool          ---
	@(link_name="ImGui_EndChild")     EndChild     :: proc()                                                                                                           ---
	// Windows Utilities
	// - 'current window' = the window we are appending into while inside a Begin()/End() block. 'next window' = next window we will Begin() into.
	@(link_name="ImGui_IsWindowAppearing") IsWindowAppearing :: proc() -> bool                         ---
	@(link_name="ImGui_IsWindowCollapsed") IsWindowCollapsed :: proc() -> bool                         ---
	@(link_name="ImGui_IsWindowFocused")   IsWindowFocused   :: proc(flags: FocusedFlags = {}) -> bool --- // is current window focused? or its root/child, depending on flags. see flags for options.
	@(link_name="ImGui_IsWindowHovered")   IsWindowHovered   :: proc(flags: HoveredFlags = {}) -> bool --- // is current window hovered and hoverable (e.g. not blocked by a popup/modal)? See ImGuiHoveredFlags_ for options. IMPORTANT: If you are trying to check whether your mouse should be dispatched to Dear ImGui or to your underlying app, you should not use this function! Use the 'io.WantCaptureMouse' boolean for that! Refer to FAQ entry "How can I tell whether to dispatch mouse/keyboard to Dear ImGui or my application?" for details.
	@(link_name="ImGui_GetWindowDrawList") GetWindowDrawList :: proc() -> ^DrawList                    --- // get draw list associated to the current window, to append your own drawing primitives
	@(link_name="ImGui_GetWindowDpiScale") GetWindowDpiScale :: proc() -> f32                          --- // get DPI scale currently associated to the current window's viewport.
	@(link_name="ImGui_GetWindowPos")      GetWindowPos      :: proc() -> Vec2                         --- // get current window position in screen space (IT IS UNLIKELY YOU EVER NEED TO USE THIS. Consider always using GetCursorScreenPos() and GetContentRegionAvail() instead)
	@(link_name="ImGui_GetWindowSize")     GetWindowSize     :: proc() -> Vec2                         --- // get current window size (IT IS UNLIKELY YOU EVER NEED TO USE THIS. Consider always using GetCursorScreenPos() and GetContentRegionAvail() instead)
	@(link_name="ImGui_GetWindowWidth")    GetWindowWidth    :: proc() -> f32                          --- // get current window width (IT IS UNLIKELY YOU EVER NEED TO USE THIS). Shortcut for GetWindowSize().x.
	@(link_name="ImGui_GetWindowHeight")   GetWindowHeight   :: proc() -> f32                          --- // get current window height (IT IS UNLIKELY YOU EVER NEED TO USE THIS). Shortcut for GetWindowSize().y.
	@(link_name="ImGui_GetWindowViewport") GetWindowViewport :: proc() -> ^Viewport                    --- // get viewport currently associated to the current window.
	// Window manipulation
	// - Prefer using SetNextXXX functions (before Begin) rather that SetXXX functions (after Begin).
	@(link_name="ImGui_SetNextWindowPos")             SetNextWindowPos             :: proc(pos: Vec2, cond: Cond = {}, pivot: Vec2 = {0, 0})                                                        --- // set next window position. call before Begin(). use pivot=(0.5f,0.5f) to center on given point, etc.
	@(link_name="ImGui_SetNextWindowSize")            SetNextWindowSize            :: proc(size: Vec2, cond: Cond = {})                                                                             --- // set next window size. set axis to 0.0f to force an auto-fit on this axis. call before Begin()
	@(link_name="ImGui_SetNextWindowSizeConstraints") SetNextWindowSizeConstraints :: proc(size_min: Vec2, size_max: Vec2, custom_callback: SizeCallback = nil, custom_callback_data: rawptr = nil) --- // set next window size limits. use 0.0f or FLT_MAX if you don't want limits. Use -1 for both min and max of same axis to preserve current size (which itself is a constraint). Use callback to apply non-trivial programmatic constraints.
	@(link_name="ImGui_SetNextWindowContentSize")     SetNextWindowContentSize     :: proc(size: Vec2)                                                                                              --- // set next window content size (~ scrollable client area, which enforce the range of scrollbars). Not including window decorations (title bar, menu bar, etc.) nor WindowPadding. set an axis to 0.0f to leave it automatic. call before Begin()
	@(link_name="ImGui_SetNextWindowCollapsed")       SetNextWindowCollapsed       :: proc(collapsed: bool, cond: Cond = {})                                                                        --- // set next window collapsed state. call before Begin()
	@(link_name="ImGui_SetNextWindowFocus")           SetNextWindowFocus           :: proc()                                                                                                        --- // set next window to be focused / top-most. call before Begin()
	@(link_name="ImGui_SetNextWindowScroll")          SetNextWindowScroll          :: proc(scroll: Vec2)                                                                                            --- // set next window scrolling value (use < 0.0f to not affect a given axis).
	@(link_name="ImGui_SetNextWindowBgAlpha")         SetNextWindowBgAlpha         :: proc(alpha: f32)                                                                                              --- // set next window background color alpha. helper to easily override the Alpha component of ImGuiCol_WindowBg/ChildBg/PopupBg. you may also use ImGuiWindowFlags_NoBackground.
	@(link_name="ImGui_SetNextWindowViewport")        SetNextWindowViewport        :: proc(viewport_id: ID)                                                                                         --- // set next window viewport
	@(link_name="ImGui_SetWindowPos")                 SetWindowPos                 :: proc(pos: Vec2, cond: Cond = {})                                                                              --- // (not recommended) set current window position - call within Begin()/End(). prefer using SetNextWindowPos(), as this may incur tearing and side-effects.
	@(link_name="ImGui_SetWindowSize")                SetWindowSize                :: proc(size: Vec2, cond: Cond = {})                                                                             --- // (not recommended) set current window size - call within Begin()/End(). set to ImVec2(0, 0) to force an auto-fit. prefer using SetNextWindowSize(), as this may incur tearing and minor side-effects.
	@(link_name="ImGui_SetWindowCollapsed")           SetWindowCollapsed           :: proc(collapsed: bool, cond: Cond = {})                                                                        --- // (not recommended) set current window collapsed state. prefer using SetNextWindowCollapsed().
	@(link_name="ImGui_SetWindowFocus")               SetWindowFocus               :: proc()                                                                                                        --- // (not recommended) set current window to be focused / top-most. prefer using SetNextWindowFocus().
	@(link_name="ImGui_SetWindowFontScale")           SetWindowFontScale           :: proc(scale: f32)                                                                                              --- // [OBSOLETE] set font scale. Adjust IO.FontGlobalScale if you want to scale all windows. This is an old API! For correct scaling, prefer to reload font + rebuild ImFontAtlas + call style.ScaleAllSizes().
	@(link_name="ImGui_SetWindowPosStr")              SetWindowPosStr              :: proc(name: cstring, pos: Vec2, cond: Cond = {})                                                               --- // set named window position.
	@(link_name="ImGui_SetWindowSizeStr")             SetWindowSizeStr             :: proc(name: cstring, size: Vec2, cond: Cond = {})                                                              --- // set named window size. set axis to 0.0f to force an auto-fit on this axis.
	@(link_name="ImGui_SetWindowCollapsedStr")        SetWindowCollapsedStr        :: proc(name: cstring, collapsed: bool, cond: Cond = {})                                                         --- // set named window collapsed state
	@(link_name="ImGui_SetWindowFocusStr")            SetWindowFocusStr            :: proc(name: cstring)                                                                                           --- // set named window to be focused / top-most. use NULL to remove focus.
	// Windows Scrolling
	// - Any change of Scroll will be applied at the beginning of next frame in the first call to Begin().
	// - You may instead use SetNextWindowScroll() prior to calling Begin() to avoid this delay, as an alternative to using SetScrollX()/SetScrollY().
	@(link_name="ImGui_GetScrollX")        GetScrollX        :: proc() -> f32                                 --- // get scrolling amount [0 .. GetScrollMaxX()]
	@(link_name="ImGui_GetScrollY")        GetScrollY        :: proc() -> f32                                 --- // get scrolling amount [0 .. GetScrollMaxY()]
	@(link_name="ImGui_SetScrollX")        SetScrollX        :: proc(scroll_x: f32)                           --- // set scrolling amount [0 .. GetScrollMaxX()]
	@(link_name="ImGui_SetScrollY")        SetScrollY        :: proc(scroll_y: f32)                           --- // set scrolling amount [0 .. GetScrollMaxY()]
	@(link_name="ImGui_GetScrollMaxX")     GetScrollMaxX     :: proc() -> f32                                 --- // get maximum scrolling amount ~~ ContentSize.x - WindowSize.x - DecorationsSize.x
	@(link_name="ImGui_GetScrollMaxY")     GetScrollMaxY     :: proc() -> f32                                 --- // get maximum scrolling amount ~~ ContentSize.y - WindowSize.y - DecorationsSize.y
	@(link_name="ImGui_SetScrollHereX")    SetScrollHereX    :: proc(center_x_ratio: f32 = 0.5)               --- // adjust scrolling amount to make current cursor position visible. center_x_ratio=0.0: left, 0.5: center, 1.0: right. When using to make a "default/current item" visible, consider using SetItemDefaultFocus() instead.
	@(link_name="ImGui_SetScrollHereY")    SetScrollHereY    :: proc(center_y_ratio: f32 = 0.5)               --- // adjust scrolling amount to make current cursor position visible. center_y_ratio=0.0: top, 0.5: center, 1.0: bottom. When using to make a "default/current item" visible, consider using SetItemDefaultFocus() instead.
	@(link_name="ImGui_SetScrollFromPosX") SetScrollFromPosX :: proc(local_x: f32, center_x_ratio: f32 = 0.5) --- // adjust scrolling amount to make given position visible. Generally GetCursorStartPos() + offset to compute a valid position.
	@(link_name="ImGui_SetScrollFromPosY") SetScrollFromPosY :: proc(local_y: f32, center_y_ratio: f32 = 0.5) --- // adjust scrolling amount to make given position visible. Generally GetCursorStartPos() + offset to compute a valid position.
	// Parameters stacks (shared)
	@(link_name="ImGui_PushFont")             PushFont             :: proc(font: ^Font)                      --- // use NULL as a shortcut to push default font
	@(link_name="ImGui_PopFont")              PopFont              :: proc()                                 ---
	@(link_name="ImGui_PushStyleColor")       PushStyleColor       :: proc(idx: Col, col: u32)               --- // modify a style color. always use this if you modify the style after NewFrame().
	@(link_name="ImGui_PushStyleColorImVec4") PushStyleColorImVec4 :: proc(idx: Col, col: Vec4)              ---
	@(link_name="ImGui_PopStyleColor")        PopStyleColor        :: proc(count: c.int = 1)                 ---
	@(link_name="ImGui_PushStyleVar")         PushStyleVar         :: proc(idx: StyleVar, val: f32)          --- // modify a style float variable. always use this if you modify the style after NewFrame()!
	@(link_name="ImGui_PushStyleVarImVec2")   PushStyleVarImVec2   :: proc(idx: StyleVar, val: Vec2)         --- // modify a style ImVec2 variable. "
	@(link_name="ImGui_PushStyleVarX")        PushStyleVarX        :: proc(idx: StyleVar, val_x: f32)        --- // modify X component of a style ImVec2 variable. "
	@(link_name="ImGui_PushStyleVarY")        PushStyleVarY        :: proc(idx: StyleVar, val_y: f32)        --- // modify Y component of a style ImVec2 variable. "
	@(link_name="ImGui_PopStyleVar")          PopStyleVar          :: proc(count: c.int = 1)                 ---
	@(link_name="ImGui_PushItemFlag")         PushItemFlag         :: proc(option: ItemFlags, enabled: bool) --- // modify specified shared item flag, e.g. PushItemFlag(ImGuiItemFlags_NoTabStop, true)
	@(link_name="ImGui_PopItemFlag")          PopItemFlag          :: proc()                                 ---
	// Parameters stacks (current window)
	@(link_name="ImGui_PushItemWidth")    PushItemWidth    :: proc(item_width: f32)             --- // push width of items for common large "item+label" widgets. >0.0f: width in pixels, <0.0f align xx pixels to the right of window (so -FLT_MIN always align width to the right side).
	@(link_name="ImGui_PopItemWidth")     PopItemWidth     :: proc()                            ---
	@(link_name="ImGui_SetNextItemWidth") SetNextItemWidth :: proc(item_width: f32)             --- // set width of the _next_ common large "item+label" widget. >0.0f: width in pixels, <0.0f align xx pixels to the right of window (so -FLT_MIN always align width to the right side)
	@(link_name="ImGui_CalcItemWidth")    CalcItemWidth    :: proc() -> f32                     --- // width of item given pushed settings and current cursor position. NOT necessarily the width of last item unlike most 'Item' functions.
	@(link_name="ImGui_PushTextWrapPos")  PushTextWrapPos  :: proc(wrap_local_pos_x: f32 = 0.0) --- // push word-wrapping position for Text*() commands. < 0.0f: no wrapping; 0.0f: wrap to end of window (or column); > 0.0f: wrap at 'wrap_pos_x' position in window local space
	@(link_name="ImGui_PopTextWrapPos")   PopTextWrapPos   :: proc()                            ---
	// Style read access
	// - Use the ShowStyleEditor() function to interactively see/edit the colors.
	@(link_name="ImGui_GetFont")                GetFont                :: proc() -> ^Font                             --- // get current font
	@(link_name="ImGui_GetFontSize")            GetFontSize            :: proc() -> f32                               --- // get current font size (= height in pixels) of current font with current scale applied
	@(link_name="ImGui_GetFontTexUvWhitePixel") GetFontTexUvWhitePixel :: proc() -> Vec2                              --- // get UV coordinate for a white pixel, useful to draw custom shapes via the ImDrawList API
	@(link_name="ImGui_GetColorU32")            GetColorU32            :: proc(idx: Col, alpha_mul: f32 = 1.0) -> u32 --- // retrieve given style color with style alpha applied and optional extra alpha multiplier, packed as a 32-bit value suitable for ImDrawList
	@(link_name="ImGui_GetColorU32ImVec4")      GetColorU32ImVec4      :: proc(col: Vec4) -> u32                      --- // retrieve given color with style alpha applied, packed as a 32-bit value suitable for ImDrawList
	@(link_name="ImGui_GetColorU32ImU32")       GetColorU32ImU32       :: proc(col: u32, alpha_mul: f32 = 1.0) -> u32 --- // retrieve given color with style alpha applied, packed as a 32-bit value suitable for ImDrawList
	@(link_name="ImGui_GetStyleColorVec4")      GetStyleColorVec4      :: proc(idx: Col) -> ^Vec4                     --- // retrieve style color as stored in ImGuiStyle structure. use to feed back into PushStyleColor(), otherwise use GetColorU32() to get style color with style alpha baked in.
	// Layout cursor positioning
	// - By "cursor" we mean the current output position.
	// - The typical widget behavior is to output themselves at the current cursor position, then move the cursor one line down.
	// - You can call SameLine() between widgets to undo the last carriage return and output at the right of the preceding widget.
	// - YOU CAN DO 99% OF WHAT YOU NEED WITH ONLY GetCursorScreenPos() and GetContentRegionAvail().
	// - Attention! We currently have inconsistencies between window-local and absolute positions we will aim to fix with future API:
	//    - Absolute coordinate:        GetCursorScreenPos(), SetCursorScreenPos(), all ImDrawList:: functions. -> this is the preferred way forward.
	//    - Window-local coordinates:   SameLine(offset), GetCursorPos(), SetCursorPos(), GetCursorStartPos(), PushTextWrapPos()
	//    - Window-local coordinates:   GetContentRegionMax(), GetWindowContentRegionMin(), GetWindowContentRegionMax() --> all obsoleted. YOU DON'T NEED THEM.
	// - GetCursorScreenPos() = GetCursorPos() + GetWindowPos(). GetWindowPos() is almost only ever useful to convert from window-local to absolute coordinates. Try not to use it.
	@(link_name="ImGui_GetCursorScreenPos")    GetCursorScreenPos    :: proc() -> Vec2        --- // cursor position, absolute coordinates. THIS IS YOUR BEST FRIEND (prefer using this rather than GetCursorPos(), also more useful to work with ImDrawList API).
	@(link_name="ImGui_SetCursorScreenPos")    SetCursorScreenPos    :: proc(pos: Vec2)       --- // cursor position, absolute coordinates. THIS IS YOUR BEST FRIEND.
	@(link_name="ImGui_GetContentRegionAvail") GetContentRegionAvail :: proc() -> Vec2        --- // available space from current position. THIS IS YOUR BEST FRIEND.
	@(link_name="ImGui_GetCursorPos")          GetCursorPos          :: proc() -> Vec2        --- // [window-local] cursor position in window-local coordinates. This is not your best friend.
	@(link_name="ImGui_GetCursorPosX")         GetCursorPosX         :: proc() -> f32         --- // [window-local] "
	@(link_name="ImGui_GetCursorPosY")         GetCursorPosY         :: proc() -> f32         --- // [window-local] "
	@(link_name="ImGui_SetCursorPos")          SetCursorPos          :: proc(local_pos: Vec2) --- // [window-local] "
	@(link_name="ImGui_SetCursorPosX")         SetCursorPosX         :: proc(local_x: f32)    --- // [window-local] "
	@(link_name="ImGui_SetCursorPosY")         SetCursorPosY         :: proc(local_y: f32)    --- // [window-local] "
	@(link_name="ImGui_GetCursorStartPos")     GetCursorStartPos     :: proc() -> Vec2        --- // [window-local] initial cursor position, in window-local coordinates. Call GetCursorScreenPos() after Begin() to get the absolute coordinates version.
	// Other layout functions
	@(link_name="ImGui_Separator")                    Separator                    :: proc()                                                    --- // separator, generally horizontal. inside a menu bar or in horizontal layout mode, this becomes a vertical separator.
	@(link_name="ImGui_SameLine")                     SameLine                     :: proc(offset_from_start_x: f32 = 0.0, spacing: f32 = -1.0) --- // call between widgets or groups to layout them horizontally. X position given in window coordinates.
	@(link_name="ImGui_NewLine")                      NewLine                      :: proc()                                                    --- // undo a SameLine() or force a new line when in a horizontal-layout context.
	@(link_name="ImGui_Spacing")                      Spacing                      :: proc()                                                    --- // add vertical spacing.
	@(link_name="ImGui_Dummy")                        Dummy                        :: proc(size: Vec2)                                          --- // add a dummy item of given size. unlike InvisibleButton(), Dummy() won't take the mouse click or be navigable into.
	@(link_name="ImGui_Indent")                       Indent                       :: proc(indent_w: f32 = 0.0)                                 --- // move content position toward the right, by indent_w, or style.IndentSpacing if indent_w <= 0
	@(link_name="ImGui_Unindent")                     Unindent                     :: proc(indent_w: f32 = 0.0)                                 --- // move content position back to the left, by indent_w, or style.IndentSpacing if indent_w <= 0
	@(link_name="ImGui_BeginGroup")                   BeginGroup                   :: proc()                                                    --- // lock horizontal starting position
	@(link_name="ImGui_EndGroup")                     EndGroup                     :: proc()                                                    --- // unlock horizontal starting position + capture the whole group bounding box into one "item" (so you can use IsItemHovered() or layout primitives such as SameLine() on whole group, etc.)
	@(link_name="ImGui_AlignTextToFramePadding")      AlignTextToFramePadding      :: proc()                                                    --- // vertically align upcoming text baseline to FramePadding.y so that it will align properly to regularly framed items (call if you have text on a line before a framed item)
	@(link_name="ImGui_GetTextLineHeight")            GetTextLineHeight            :: proc() -> f32                                             --- // ~ FontSize
	@(link_name="ImGui_GetTextLineHeightWithSpacing") GetTextLineHeightWithSpacing :: proc() -> f32                                             --- // ~ FontSize + style.ItemSpacing.y (distance in pixels between 2 consecutive lines of text)
	@(link_name="ImGui_GetFrameHeight")               GetFrameHeight               :: proc() -> f32                                             --- // ~ FontSize + style.FramePadding.y * 2
	@(link_name="ImGui_GetFrameHeightWithSpacing")    GetFrameHeightWithSpacing    :: proc() -> f32                                             --- // ~ FontSize + style.FramePadding.y * 2 + style.ItemSpacing.y (distance in pixels between 2 consecutive lines of framed widgets)
	// ID stack/scopes
	// Read the FAQ (docs/FAQ.md or http://dearimgui.com/faq) for more details about how ID are handled in dear imgui.
	// - Those questions are answered and impacted by understanding of the ID stack system:
	//   - "Q: Why is my widget not reacting when I click on it?"
	//   - "Q: How can I have widgets with an empty label?"
	//   - "Q: How can I have multiple widgets with the same label?"
	// - Short version: ID are hashes of the entire ID stack. If you are creating widgets in a loop you most likely
	//   want to push a unique identifier (e.g. object pointer, loop index) to uniquely differentiate them.
	// - You can also use the "Label##foobar" syntax within widget label to distinguish them from each others.
	// - In this header file we use the "label"/"name" terminology to denote a string that will be displayed + used as an ID,
	//   whereas "str_id" denote a string that is only used as an ID and not normally displayed.
	@(link_name="ImGui_PushID")    PushID    :: proc(str_id: cstring)                                  --- // push string into the ID stack (will hash string).
	@(link_name="ImGui_PushIDStr") PushIDStr :: proc(str_id_begin: cstring, str_id_end: cstring)       --- // push string into the ID stack (will hash string).
	@(link_name="ImGui_PushIDPtr") PushIDPtr :: proc(ptr_id: rawptr)                                   --- // push pointer into the ID stack (will hash pointer).
	@(link_name="ImGui_PushIDInt") PushIDInt :: proc(int_id: c.int)                                    --- // push integer into the ID stack (will hash integer).
	@(link_name="ImGui_PopID")     PopID     :: proc()                                                 --- // pop from the ID stack.
	@(link_name="ImGui_GetID")     GetID     :: proc(str_id: cstring) -> ID                            --- // calculate unique ID (hash of whole ID stack + given parameter). e.g. if you want to query into ImGuiStorage yourself
	@(link_name="ImGui_GetIDStr")  GetIDStr  :: proc(str_id_begin: cstring, str_id_end: cstring) -> ID ---
	@(link_name="ImGui_GetIDPtr")  GetIDPtr  :: proc(ptr_id: rawptr) -> ID                             ---
	@(link_name="ImGui_GetIDInt")  GetIDInt  :: proc(int_id: c.int) -> ID                              ---
	// Widgets: Text
	@(link_name="ImGui_TextUnformatted") TextUnformatted :: proc(text: cstring, text_end: cstring = nil)              --- // raw text without formatting. Roughly equivalent to Text("%s", text) but: A) doesn't require null terminated string if 'text_end' is specified, B) it's faster, no memory copy is done, no buffer size limits, recommended for long chunks of text.
	@(link_name="ImGui_Text")            Text            :: proc(fmt: cstring, #c_vararg args: ..any)                 --- // formatted text
	@(link_name="ImGui_TextColored")     TextColored     :: proc(col: Vec4, fmt: cstring, #c_vararg args: ..any)      --- // shortcut for PushStyleColor(ImGuiCol_Text, col); Text(fmt, ...); PopStyleColor();
	@(link_name="ImGui_TextDisabled")    TextDisabled    :: proc(fmt: cstring, #c_vararg args: ..any)                 --- // shortcut for PushStyleColor(ImGuiCol_Text, style.Colors[ImGuiCol_TextDisabled]); Text(fmt, ...); PopStyleColor();
	@(link_name="ImGui_TextWrapped")     TextWrapped     :: proc(fmt: cstring, #c_vararg args: ..any)                 --- // shortcut for PushTextWrapPos(0.0f); Text(fmt, ...); PopTextWrapPos();. Note that this won't work on an auto-resizing window if there's no other widgets to extend the window width, yoy may need to set a size using SetNextWindowSize().
	@(link_name="ImGui_LabelText")       LabelText       :: proc(label: cstring, fmt: cstring, #c_vararg args: ..any) --- // display text+label aligned the same way as value+label widgets
	@(link_name="ImGui_BulletText")      BulletText      :: proc(fmt: cstring, #c_vararg args: ..any)                 --- // shortcut for Bullet()+Text()
	@(link_name="ImGui_SeparatorText")   SeparatorText   :: proc(label: cstring)                                      --- // currently: formatted text with an horizontal line
	// Widgets: Main
	// - Most widgets return true when the value has been changed or when pressed/selected
	// - You may also use one of the many IsItemXXX functions (e.g. IsItemActive, IsItemHovered, etc.) to query widget state.
	@(link_name="ImGui_Button")               Button               :: proc(label: cstring, size: Vec2 = {0, 0}) -> bool                            --- // button
	@(link_name="ImGui_SmallButton")          SmallButton          :: proc(label: cstring) -> bool                                                 --- // button with (FramePadding.y == 0) to easily embed within text
	@(link_name="ImGui_InvisibleButton")      InvisibleButton      :: proc(str_id: cstring, size: Vec2, flags: ButtonFlags = {}) -> bool           --- // flexible button behavior without the visuals, frequently useful to build custom behaviors using the public api (along with IsItemActive, IsItemHovered, etc.)
	@(link_name="ImGui_ArrowButton")          ArrowButton          :: proc(str_id: cstring, dir: Dir) -> bool                                      --- // square button with an arrow shape
	@(link_name="ImGui_Checkbox")             Checkbox             :: proc(label: cstring, v: ^bool) -> bool                                       ---
	@(link_name="ImGui_CheckboxFlagsIntPtr")  CheckboxFlagsIntPtr  :: proc(label: cstring, flags: ^c.int, flags_value: c.int) -> bool              ---
	@(link_name="ImGui_CheckboxFlagsUintPtr") CheckboxFlagsUintPtr :: proc(label: cstring, flags: ^c.uint, flags_value: c.uint) -> bool            ---
	@(link_name="ImGui_RadioButton")          RadioButton          :: proc(label: cstring, active: bool) -> bool                                   --- // use with e.g. if (RadioButton("one", my_value==1)) { my_value = 1; }
	@(link_name="ImGui_RadioButtonIntPtr")    RadioButtonIntPtr    :: proc(label: cstring, v: ^c.int, v_button: c.int) -> bool                     --- // shortcut to handle the above pattern when value is an integer
	@(link_name="ImGui_ProgressBar")          ProgressBar          :: proc(fraction: f32, size_arg: Vec2 = {-min(f32), 0}, overlay: cstring = nil) ---
	@(link_name="ImGui_Bullet")               Bullet               :: proc()                                                                       --- // draw a small circle + keep the cursor on the same line. advance cursor x position by GetTreeNodeToLabelSpacing(), same distance that TreeNode() uses
	@(link_name="ImGui_TextLink")             TextLink             :: proc(label: cstring) -> bool                                                 --- // hyperlink text button, return true when clicked
	@(link_name="ImGui_TextLinkOpenURL")      TextLinkOpenURL      :: proc(label: cstring, url: cstring = nil)                                     --- // hyperlink text button, automatically open file/url when clicked
	// Widgets: Images
	// - Read about ImTextureID here: https://github.com/ocornut/imgui/wiki/Image-Loading-and-Displaying-Examples
	// - 'uv0' and 'uv1' are texture coordinates. Read about them from the same link above.
	// - Note that Image() may add +2.0f to provided size if a border is visible, ImageButton() adds style.FramePadding*2.0f to provided size.
	// - ImageButton() draws a background based on regular Button() color + optionally an inner background if specified.
	@(link_name="ImGui_Image")       Image       :: proc(user_texture_id: TextureID, image_size: Vec2, uv0: Vec2 = {0, 0}, uv1: Vec2 = {1, 1}, tint_col: Vec4 = {1, 1, 1, 1}, border_col: Vec4 = {0, 0, 0, 0})                      ---
	@(link_name="ImGui_ImageButton") ImageButton :: proc(str_id: cstring, user_texture_id: TextureID, image_size: Vec2, uv0: Vec2 = {0, 0}, uv1: Vec2 = {1, 1}, bg_col: Vec4 = {0, 0, 0, 0}, tint_col: Vec4 = {1, 1, 1, 1}) -> bool ---
	// Widgets: Combo Box (Dropdown)
	// - The BeginCombo()/EndCombo() api allows you to manage your contents and selection state however you want it, by creating e.g. Selectable() items.
	// - The old Combo() api are helpers over BeginCombo()/EndCombo() which are kept available for convenience purpose. This is analogous to how ListBox are created.
	@(link_name="ImGui_BeginCombo")    BeginCombo    :: proc(label: cstring, preview_value: cstring, flags: ComboFlags = {}) -> bool                                                                                                                  ---
	@(link_name="ImGui_EndCombo")      EndCombo      :: proc()                                                                                                                                                                                        --- // only call EndCombo() if BeginCombo() returns true!
	@(link_name="ImGui_ComboChar")     ComboChar     :: proc(label: cstring, current_item: ^c.int, items: [^]cstring, items_count: c.int, popup_max_height_in_items: c.int = -1) -> bool                                                              ---
	@(link_name="ImGui_Combo")         Combo         :: proc(label: cstring, current_item: ^c.int, items_separated_by_zeros: cstring, popup_max_height_in_items: c.int = -1) -> bool                                                                  --- // Separate items with \0 within a string, end item-list with \0\0. e.g. "One\0Two\0Three\0"
	@(link_name="ImGui_ComboCallback") ComboCallback :: proc(label: cstring, current_item: ^c.int, getter: proc "c" (user_data: rawptr, idx: c.int) -> cstring, user_data: rawptr, items_count: c.int, popup_max_height_in_items: c.int = -1) -> bool ---
	// Widgets: Drag Sliders
	// - CTRL+Click on any drag box to turn them into an input box. Manually input values aren't clamped by default and can go off-bounds. Use ImGuiSliderFlags_AlwaysClamp to always clamp.
	// - For all the Float2/Float3/Float4/Int2/Int3/Int4 versions of every function, note that a 'float v[X]' function argument is the same as 'float* v',
	//   the array syntax is just a way to document the number of elements that are expected to be accessible. You can pass address of your first element out of a contiguous set, e.g. &myvector.x
	// - Adjust format string to decorate the value with a prefix, a suffix, or adapt the editing and display precision e.g. "%.3f" -> 1.234; "%5.2f secs" -> 01.23 secs; "Biscuit: %.0f" -> Biscuit: 1; etc.
	// - Format string may also be set to NULL or use the default format ("%f" or "%d").
	// - Speed are per-pixel of mouse movement (v_speed=0.2f: mouse needs to move by 5 pixels to increase value by 1). For keyboard/gamepad navigation, minimum speed is Max(v_speed, minimum_step_at_given_precision).
	// - Use v_min < v_max to clamp edits to given limits. Note that CTRL+Click manual input can override those limits if ImGuiSliderFlags_AlwaysClamp is not used.
	// - Use v_max = FLT_MAX / INT_MAX etc to avoid clamping to a maximum, same with v_min = -FLT_MAX / INT_MIN to avoid clamping to a minimum.
	// - We use the same sets of flags for DragXXX() and SliderXXX() functions as the features are the same and it makes it easier to swap them.
	// - Legacy: Pre-1.78 there are DragXXX() function signatures that take a final `float power=1.0f' argument instead of the `ImGuiSliderFlags flags=0' argument.
	//   If you get a warning converting a float to ImGuiSliderFlags, read https://github.com/ocornut/imgui/issues/3361
	@(link_name="ImGui_DragFloat")       DragFloat       :: proc(label: cstring, v: ^f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                                                 --- // If v_min >= v_max we have no bound
	@(link_name="ImGui_DragFloat2")      DragFloat2      :: proc(label: cstring, v: ^[2]f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                                              ---
	@(link_name="ImGui_DragFloat3")      DragFloat3      :: proc(label: cstring, v: ^[3]f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                                              ---
	@(link_name="ImGui_DragFloat4")      DragFloat4      :: proc(label: cstring, v: ^[4]f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                                              ---
	@(link_name="ImGui_DragFloatRange2") DragFloatRange2 :: proc(label: cstring, v_current_min: ^f32, v_current_max: ^f32, v_speed: f32 = 1.0, v_min: f32 = 0.0, v_max: f32 = 0.0, format: cstring = "%.3f", format_max: cstring = nil, flags: SliderFlags = {}) -> bool     ---
	@(link_name="ImGui_DragInt")         DragInt         :: proc(label: cstring, v: ^c.int, v_speed: f32 = 1.0, v_min: c.int = {}, v_max: c.int = {}, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                                               --- // If v_min >= v_max we have no bound
	@(link_name="ImGui_DragInt2")        DragInt2        :: proc(label: cstring, v: ^[2]c.int, v_speed: f32 = 1.0, v_min: c.int = {}, v_max: c.int = {}, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                                            ---
	@(link_name="ImGui_DragInt3")        DragInt3        :: proc(label: cstring, v: ^[3]c.int, v_speed: f32 = 1.0, v_min: c.int = {}, v_max: c.int = {}, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                                            ---
	@(link_name="ImGui_DragInt4")        DragInt4        :: proc(label: cstring, v: ^[4]c.int, v_speed: f32 = 1.0, v_min: c.int = {}, v_max: c.int = {}, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                                            ---
	@(link_name="ImGui_DragIntRange2")   DragIntRange2   :: proc(label: cstring, v_current_min: ^c.int, v_current_max: ^c.int, v_speed: f32 = 1.0, v_min: c.int = {}, v_max: c.int = {}, format: cstring = "%d", format_max: cstring = nil, flags: SliderFlags = {}) -> bool ---
	@(link_name="ImGui_DragScalar")      DragScalar      :: proc(label: cstring, data_type: DataType, p_data: rawptr, v_speed: f32 = 1.0, p_min: rawptr = nil, p_max: rawptr = nil, format: cstring = nil, flags: SliderFlags = {}) -> bool                                  ---
	@(link_name="ImGui_DragScalarN")     DragScalarN     :: proc(label: cstring, data_type: DataType, p_data: rawptr, components: c.int, v_speed: f32 = 1.0, p_min: rawptr = nil, p_max: rawptr = nil, format: cstring = nil, flags: SliderFlags = {}) -> bool               ---
	// Widgets: Regular Sliders
	// - CTRL+Click on any slider to turn them into an input box. Manually input values aren't clamped by default and can go off-bounds. Use ImGuiSliderFlags_AlwaysClamp to always clamp.
	// - Adjust format string to decorate the value with a prefix, a suffix, or adapt the editing and display precision e.g. "%.3f" -> 1.234; "%5.2f secs" -> 01.23 secs; "Biscuit: %.0f" -> Biscuit: 1; etc.
	// - Format string may also be set to NULL or use the default format ("%f" or "%d").
	// - Legacy: Pre-1.78 there are SliderXXX() function signatures that take a final `float power=1.0f' argument instead of the `ImGuiSliderFlags flags=0' argument.
	//   If you get a warning converting a float to ImGuiSliderFlags, read https://github.com/ocornut/imgui/issues/3361
	@(link_name="ImGui_SliderFloat")   SliderFloat   :: proc(label: cstring, v: ^f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                                   --- // adjust format to decorate the value with a prefix or a suffix for in-slider labels or unit display.
	@(link_name="ImGui_SliderFloat2")  SliderFloat2  :: proc(label: cstring, v: ^[2]f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                                ---
	@(link_name="ImGui_SliderFloat3")  SliderFloat3  :: proc(label: cstring, v: ^[3]f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                                ---
	@(link_name="ImGui_SliderFloat4")  SliderFloat4  :: proc(label: cstring, v: ^[4]f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                                ---
	@(link_name="ImGui_SliderAngle")   SliderAngle   :: proc(label: cstring, v_rad: ^f32, v_degrees_min: f32 = -360.0, v_degrees_max: f32 = +360.0, format: cstring = "%.0f deg", flags: SliderFlags = {}) -> bool         ---
	@(link_name="ImGui_SliderInt")     SliderInt     :: proc(label: cstring, v: ^c.int, v_min: c.int, v_max: c.int, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                               ---
	@(link_name="ImGui_SliderInt2")    SliderInt2    :: proc(label: cstring, v: ^[2]c.int, v_min: c.int, v_max: c.int, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                            ---
	@(link_name="ImGui_SliderInt3")    SliderInt3    :: proc(label: cstring, v: ^[3]c.int, v_min: c.int, v_max: c.int, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                            ---
	@(link_name="ImGui_SliderInt4")    SliderInt4    :: proc(label: cstring, v: ^[4]c.int, v_min: c.int, v_max: c.int, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                            ---
	@(link_name="ImGui_SliderScalar")  SliderScalar  :: proc(label: cstring, data_type: DataType, p_data: rawptr, p_min: rawptr, p_max: rawptr, format: cstring = nil, flags: SliderFlags = {}) -> bool                    ---
	@(link_name="ImGui_SliderScalarN") SliderScalarN :: proc(label: cstring, data_type: DataType, p_data: rawptr, components: c.int, p_min: rawptr, p_max: rawptr, format: cstring = nil, flags: SliderFlags = {}) -> bool ---
	@(link_name="ImGui_VSliderFloat")  VSliderFloat  :: proc(label: cstring, size: Vec2, v: ^f32, v_min: f32, v_max: f32, format: cstring = "%.3f", flags: SliderFlags = {}) -> bool                                       ---
	@(link_name="ImGui_VSliderInt")    VSliderInt    :: proc(label: cstring, size: Vec2, v: ^c.int, v_min: c.int, v_max: c.int, format: cstring = "%d", flags: SliderFlags = {}) -> bool                                   ---
	@(link_name="ImGui_VSliderScalar") VSliderScalar :: proc(label: cstring, size: Vec2, data_type: DataType, p_data: rawptr, p_min: rawptr, p_max: rawptr, format: cstring = nil, flags: SliderFlags = {}) -> bool        ---
	// Widgets: Input with Keyboard
	// - If you want to use InputText() with std::string or any custom dynamic string type, see misc/cpp/imgui_stdlib.h and comments in imgui_demo.cpp.
	// - Most of the ImGuiInputTextFlags flags are only useful for InputText() and not for InputFloatX, InputIntX, InputDouble etc.
	@(link_name="ImGui_InputText")          InputText          :: proc(label: cstring, buf: cstring, buf_size: c.size_t, flags: InputTextFlags = {}, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool                                   ---
	@(link_name="ImGui_InputTextMultiline") InputTextMultiline :: proc(label: cstring, buf: cstring, buf_size: c.size_t, size: Vec2 = {0, 0}, flags: InputTextFlags = {}, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool              ---
	@(link_name="ImGui_InputTextWithHint")  InputTextWithHint  :: proc(label: cstring, hint: cstring, buf: cstring, buf_size: c.size_t, flags: InputTextFlags = {}, callback: InputTextCallback = nil, user_data: rawptr = nil) -> bool                    ---
	@(link_name="ImGui_InputFloat")         InputFloat         :: proc(label: cstring, v: ^f32, step: f32 = 0.0, step_fast: f32 = 0.0, format: cstring = "%.3f", flags: InputTextFlags = {}) -> bool                                                       ---
	@(link_name="ImGui_InputFloat2")        InputFloat2        :: proc(label: cstring, v: ^[2]f32, format: cstring = "%.3f", flags: InputTextFlags = {}) -> bool                                                                                           ---
	@(link_name="ImGui_InputFloat3")        InputFloat3        :: proc(label: cstring, v: ^[3]f32, format: cstring = "%.3f", flags: InputTextFlags = {}) -> bool                                                                                           ---
	@(link_name="ImGui_InputFloat4")        InputFloat4        :: proc(label: cstring, v: ^[4]f32, format: cstring = "%.3f", flags: InputTextFlags = {}) -> bool                                                                                           ---
	@(link_name="ImGui_InputInt")           InputInt           :: proc(label: cstring, v: ^c.int, step: c.int = 1, step_fast: c.int = 100, flags: InputTextFlags = {}) -> bool                                                                             ---
	@(link_name="ImGui_InputInt2")          InputInt2          :: proc(label: cstring, v: ^[2]c.int, flags: InputTextFlags = {}) -> bool                                                                                                                   ---
	@(link_name="ImGui_InputInt3")          InputInt3          :: proc(label: cstring, v: ^[3]c.int, flags: InputTextFlags = {}) -> bool                                                                                                                   ---
	@(link_name="ImGui_InputInt4")          InputInt4          :: proc(label: cstring, v: ^[4]c.int, flags: InputTextFlags = {}) -> bool                                                                                                                   ---
	@(link_name="ImGui_InputDouble")        InputDouble        :: proc(label: cstring, v: ^f64, step: f64 = 0.0, step_fast: f64 = 0.0, format: cstring = "%.6f", flags: InputTextFlags = {}) -> bool                                                       ---
	@(link_name="ImGui_InputScalar")        InputScalar        :: proc(label: cstring, data_type: DataType, p_data: rawptr, p_step: rawptr = nil, p_step_fast: rawptr = nil, format: cstring = nil, flags: InputTextFlags = {}) -> bool                    ---
	@(link_name="ImGui_InputScalarN")       InputScalarN       :: proc(label: cstring, data_type: DataType, p_data: rawptr, components: c.int, p_step: rawptr = nil, p_step_fast: rawptr = nil, format: cstring = nil, flags: InputTextFlags = {}) -> bool ---
	// Widgets: Color Editor/Picker (tip: the ColorEdit* functions have a little color square that can be left-clicked to open a picker, and right-clicked to open an option menu.)
	// - Note that in C++ a 'float v[X]' function argument is the _same_ as 'float* v', the array syntax is just a way to document the number of elements that are expected to be accessible.
	// - You can pass the address of a first float element out of a contiguous structure, e.g. &myvector.x
	@(link_name="ImGui_ColorEdit3")          ColorEdit3          :: proc(label: cstring, col: ^[3]f32, flags: ColorEditFlags = {}) -> bool                      ---
	@(link_name="ImGui_ColorEdit4")          ColorEdit4          :: proc(label: cstring, col: ^[4]f32, flags: ColorEditFlags = {}) -> bool                      ---
	@(link_name="ImGui_ColorPicker3")        ColorPicker3        :: proc(label: cstring, col: ^[3]f32, flags: ColorEditFlags = {}) -> bool                      ---
	@(link_name="ImGui_ColorPicker4")        ColorPicker4        :: proc(label: cstring, col: ^[4]f32, flags: ColorEditFlags = {}, ref_col: ^f32 = nil) -> bool ---
	@(link_name="ImGui_ColorButton")         ColorButton         :: proc(desc_id: cstring, col: Vec4, flags: ColorEditFlags = {}, size: Vec2 = {0, 0}) -> bool  --- // display a color square/button, hover for details, return true when pressed.
	@(link_name="ImGui_SetColorEditOptions") SetColorEditOptions :: proc(flags: ColorEditFlags)                                                                 --- // initialize current options (generally on application startup) if you want to select a default format, picker type, etc. User will be able to change many settings, unless you pass the _NoOptions flag to your calls.
	// Widgets: Trees
	// - TreeNode functions return true when the node is open, in which case you need to also call TreePop() when you are finished displaying the tree node contents.
	@(link_name="ImGui_TreeNode")                  TreeNode                  :: proc(label: cstring) -> bool                                                             ---
	@(link_name="ImGui_TreeNodeStr")               TreeNodeStr               :: proc(str_id: cstring, fmt: cstring, #c_vararg args: ..any) -> bool                       --- // helper variation to easily decorelate the id from the displayed string. Read the FAQ about why and how to use ID. to align arbitrary text at the same level as a TreeNode() you can use Bullet().
	@(link_name="ImGui_TreeNodePtr")               TreeNodePtr               :: proc(ptr_id: rawptr, fmt: cstring, #c_vararg args: ..any) -> bool                        --- // "
	@(link_name="ImGui_TreeNodeEx")                TreeNodeEx                :: proc(label: cstring, flags: TreeNodeFlags = {}) -> bool                                  ---
	@(link_name="ImGui_TreeNodeExStr")             TreeNodeExStr             :: proc(str_id: cstring, flags: TreeNodeFlags, fmt: cstring, #c_vararg args: ..any) -> bool ---
	@(link_name="ImGui_TreeNodeExPtr")             TreeNodeExPtr             :: proc(ptr_id: rawptr, flags: TreeNodeFlags, fmt: cstring, #c_vararg args: ..any) -> bool  ---
	@(link_name="ImGui_TreePush")                  TreePush                  :: proc(str_id: cstring)                                                                    --- // ~ Indent()+PushID(). Already called by TreeNode() when returning true, but you can call TreePush/TreePop yourself if desired.
	@(link_name="ImGui_TreePushPtr")               TreePushPtr               :: proc(ptr_id: rawptr)                                                                     --- // "
	@(link_name="ImGui_TreePop")                   TreePop                   :: proc()                                                                                   --- // ~ Unindent()+PopID()
	@(link_name="ImGui_GetTreeNodeToLabelSpacing") GetTreeNodeToLabelSpacing :: proc() -> f32                                                                            --- // horizontal distance preceding label when using TreeNode*() or Bullet() == (g.FontSize + style.FramePadding.x*2) for a regular unframed TreeNode
	@(link_name="ImGui_CollapsingHeader")          CollapsingHeader          :: proc(label: cstring, flags: TreeNodeFlags = {}) -> bool                                  --- // if returning 'true' the header is open. doesn't indent nor push on ID stack. user doesn't have to call TreePop().
	@(link_name="ImGui_CollapsingHeaderBoolPtr")   CollapsingHeaderBoolPtr   :: proc(label: cstring, p_visible: ^bool, flags: TreeNodeFlags = {}) -> bool                --- // when 'p_visible != NULL': if '*p_visible==true' display an additional small close button on upper right of the header which will set the bool to false when clicked, if '*p_visible==false' don't display the header.
	@(link_name="ImGui_SetNextItemOpen")           SetNextItemOpen           :: proc(is_open: bool, cond: Cond = {})                                                     --- // set next TreeNode/CollapsingHeader open state.
	@(link_name="ImGui_SetNextItemStorageID")      SetNextItemStorageID      :: proc(storage_id: ID)                                                                     --- // set id to use for open/close storage (default to same as item id).
	// Widgets: Selectables
	// - A selectable highlights when hovered, and can display another color when selected.
	// - Neighbors selectable extend their highlight bounds in order to leave no gap between them. This is so a series of selected Selectable appear contiguous.
	@(link_name="ImGui_Selectable")        Selectable        :: proc(label: cstring, selected: bool = false, flags: SelectableFlags = {}, size: Vec2 = {0, 0}) -> bool --- // "bool selected" carry the selection state (read-only). Selectable() is clicked is returns true so you can modify your selection state. size.x==0.0: use remaining width, size.x>0.0: specify width. size.y==0.0: use label height, size.y>0.0: specify height
	@(link_name="ImGui_SelectableBoolPtr") SelectableBoolPtr :: proc(label: cstring, p_selected: ^bool, flags: SelectableFlags = {}, size: Vec2 = {0, 0}) -> bool      --- // "bool* p_selected" point to the selection state (read-write), as a convenient helper.
	// Multi-selection system for Selectable(), Checkbox(), TreeNode() functions [BETA]
	// - This enables standard multi-selection/range-selection idioms (CTRL+Mouse/Keyboard, SHIFT+Mouse/Keyboard, etc.) in a way that also allow a clipper to be used.
	// - ImGuiSelectionUserData is often used to store your item index within the current view (but may store something else).
	// - Read comments near ImGuiMultiSelectIO for instructions/details and see 'Demo->Widgets->Selection State & Multi-Select' for demo.
	// - TreeNode() is technically supported but... using this correctly is more complicated. You need some sort of linear/random access to your tree,
	//   which is suited to advanced trees setups already implementing filters and clipper. We will work simplifying the current demo.
	// - 'selection_size' and 'items_count' parameters are optional and used by a few features. If they are costly for you to compute, you may avoid them.
	@(link_name="ImGui_BeginMultiSelect")             BeginMultiSelect             :: proc(flags: MultiSelectFlags, selection_size: c.int = -1, items_count: c.int = -1) -> ^MultiSelectIO ---
	@(link_name="ImGui_EndMultiSelect")               EndMultiSelect               :: proc() -> ^MultiSelectIO                                                                             ---
	@(link_name="ImGui_SetNextItemSelectionUserData") SetNextItemSelectionUserData :: proc(selection_user_data: SelectionUserData)                                                         ---
	@(link_name="ImGui_IsItemToggledSelection")       IsItemToggledSelection       :: proc() -> bool                                                                                       --- // Was the last item selection state toggled? Useful if you need the per-item information _before_ reaching EndMultiSelect(). We only returns toggle _event_ in order to handle clipping correctly.
	// Widgets: List Boxes
	// - This is essentially a thin wrapper to using BeginChild/EndChild with the ImGuiChildFlags_FrameStyle flag for stylistic changes + displaying a label.
	// - If you don't need a label you can probably simply use BeginChild() with the ImGuiChildFlags_FrameStyle flag for the same result.
	// - You can submit contents and manage your selection state however you want it, by creating e.g. Selectable() or any other items.
	// - The simplified/old ListBox() api are helpers over BeginListBox()/EndListBox() which are kept available for convenience purpose. This is analoguous to how Combos are created.
	// - Choose frame width:   size.x > 0.0f: custom  /  size.x < 0.0f or -FLT_MIN: right-align   /  size.x = 0.0f (default): use current ItemWidth
	// - Choose frame height:  size.y > 0.0f: custom  /  size.y < 0.0f or -FLT_MIN: bottom-align  /  size.y = 0.0f (default): arbitrary default height which can fit ~7 items
	@(link_name="ImGui_BeginListBox")    BeginListBox    :: proc(label: cstring, size: Vec2 = {0, 0}) -> bool                                                                                                                                   --- // open a framed scrolling region
	@(link_name="ImGui_EndListBox")      EndListBox      :: proc()                                                                                                                                                                              --- // only call EndListBox() if BeginListBox() returned true!
	@(link_name="ImGui_ListBox")         ListBox         :: proc(label: cstring, current_item: ^c.int, items: [^]cstring, items_count: c.int, height_in_items: c.int = -1) -> bool                                                              ---
	@(link_name="ImGui_ListBoxCallback") ListBoxCallback :: proc(label: cstring, current_item: ^c.int, getter: proc "c" (user_data: rawptr, idx: c.int) -> cstring, user_data: rawptr, items_count: c.int, height_in_items: c.int = -1) -> bool ---
	// Widgets: Data Plotting
	// - Consider using ImPlot (https://github.com/epezent/implot) which is much better!
	@(link_name="ImGui_PlotLines")             PlotLines             :: proc(label: cstring, values: ^f32, values_count: c.int, values_offset: c.int = {}, overlay_text: cstring = nil, scale_min: f32 = max(f32), scale_max: f32 = max(f32), graph_size: Vec2 = {0, 0}, stride: c.int = size_of(f32))                              ---
	@(link_name="ImGui_PlotLinesCallback")     PlotLinesCallback     :: proc(label: cstring, values_getter: proc "c" (data: rawptr, idx: c.int) -> f32, data: rawptr, values_count: c.int, values_offset: c.int = {}, overlay_text: cstring = nil, scale_min: f32 = max(f32), scale_max: f32 = max(f32), graph_size: Vec2 = {0, 0}) ---
	@(link_name="ImGui_PlotHistogram")         PlotHistogram         :: proc(label: cstring, values: ^f32, values_count: c.int, values_offset: c.int = {}, overlay_text: cstring = nil, scale_min: f32 = max(f32), scale_max: f32 = max(f32), graph_size: Vec2 = {0, 0}, stride: c.int = size_of(f32))                              ---
	@(link_name="ImGui_PlotHistogramCallback") PlotHistogramCallback :: proc(label: cstring, values_getter: proc "c" (data: rawptr, idx: c.int) -> f32, data: rawptr, values_count: c.int, values_offset: c.int = {}, overlay_text: cstring = nil, scale_min: f32 = max(f32), scale_max: f32 = max(f32), graph_size: Vec2 = {0, 0}) ---
	// Widgets: Menus
	// - Use BeginMenuBar() on a window ImGuiWindowFlags_MenuBar to append to its menu bar.
	// - Use BeginMainMenuBar() to create a menu bar at the top of the screen and append to it.
	// - Use BeginMenu() to create a menu. You can call BeginMenu() multiple time with the same identifier to append more items to it.
	// - Not that MenuItem() keyboardshortcuts are displayed as a convenience but _not processed_ by Dear ImGui at the moment.
	@(link_name="ImGui_BeginMenuBar")     BeginMenuBar     :: proc() -> bool                                                                                      --- // append to menu-bar of current window (requires ImGuiWindowFlags_MenuBar flag set on parent window).
	@(link_name="ImGui_EndMenuBar")       EndMenuBar       :: proc()                                                                                              --- // only call EndMenuBar() if BeginMenuBar() returns true!
	@(link_name="ImGui_BeginMainMenuBar") BeginMainMenuBar :: proc() -> bool                                                                                      --- // create and append to a full screen menu-bar.
	@(link_name="ImGui_EndMainMenuBar")   EndMainMenuBar   :: proc()                                                                                              --- // only call EndMainMenuBar() if BeginMainMenuBar() returns true!
	@(link_name="ImGui_BeginMenu")        BeginMenu        :: proc(label: cstring, enabled: bool = true) -> bool                                                  --- // create a sub-menu entry. only call EndMenu() if this returns true!
	@(link_name="ImGui_EndMenu")          EndMenu          :: proc()                                                                                              --- // only call EndMenu() if BeginMenu() returns true!
	@(link_name="ImGui_MenuItem")         MenuItem         :: proc(label: cstring, shortcut: cstring = nil, selected: bool = false, enabled: bool = true) -> bool --- // return true when activated.
	@(link_name="ImGui_MenuItemBoolPtr")  MenuItemBoolPtr  :: proc(label: cstring, shortcut: cstring, p_selected: ^bool, enabled: bool = true) -> bool            --- // return true when activated + toggle (*p_selected) if p_selected != NULL
	// Tooltips
	// - Tooltips are windows following the mouse. They do not take focus away.
	// - A tooltip window can contain items of any types.
	// - SetTooltip() is more or less a shortcut for the 'if (BeginTooltip()) { Text(...); EndTooltip(); }' idiom (with a subtlety that it discard any previously submitted tooltip)
	@(link_name="ImGui_BeginTooltip") BeginTooltip :: proc() -> bool                            --- // begin/append a tooltip window.
	@(link_name="ImGui_EndTooltip")   EndTooltip   :: proc()                                    --- // only call EndTooltip() if BeginTooltip()/BeginItemTooltip() returns true!
	@(link_name="ImGui_SetTooltip")   SetTooltip   :: proc(fmt: cstring, #c_vararg args: ..any) --- // set a text-only tooltip. Often used after a ImGui::IsItemHovered() check. Override any previous call to SetTooltip().
	// Tooltips: helpers for showing a tooltip when hovering an item
	// - BeginItemTooltip() is a shortcut for the 'if (IsItemHovered(ImGuiHoveredFlags_ForTooltip) && BeginTooltip())' idiom.
	// - SetItemTooltip() is a shortcut for the 'if (IsItemHovered(ImGuiHoveredFlags_ForTooltip)) { SetTooltip(...); }' idiom.
	// - Where 'ImGuiHoveredFlags_ForTooltip' itself is a shortcut to use 'style.HoverFlagsForTooltipMouse' or 'style.HoverFlagsForTooltipNav' depending on active input type. For mouse it defaults to 'ImGuiHoveredFlags_Stationary | ImGuiHoveredFlags_DelayShort'.
	@(link_name="ImGui_BeginItemTooltip") BeginItemTooltip :: proc() -> bool                            --- // begin/append a tooltip window if preceding item was hovered.
	@(link_name="ImGui_SetItemTooltip")   SetItemTooltip   :: proc(fmt: cstring, #c_vararg args: ..any) --- // set a text-only tooltip if preceding item was hovered. override any previous call to SetTooltip().
	// Popups, Modals
	//  - They block normal mouse hovering detection (and therefore most mouse interactions) behind them.
	//  - If not modal: they can be closed by clicking anywhere outside them, or by pressing ESCAPE.
	//  - Their visibility state (~bool) is held internally instead of being held by the programmer as we are used to with regular Begin*() calls.
	//  - The 3 properties above are related: we need to retain popup visibility state in the library because popups may be closed as any time.
	//  - You can bypass the hovering restriction by using ImGuiHoveredFlags_AllowWhenBlockedByPopup when calling IsItemHovered() or IsWindowHovered().
	//  - IMPORTANT: Popup identifiers are relative to the current ID stack, so OpenPopup and BeginPopup generally needs to be at the same level of the stack.
	//    This is sometimes leading to confusing mistakes. May rework this in the future.
	//  - BeginPopup(): query popup state, if open start appending into the window. Call EndPopup() afterwards if returned true. ImGuiWindowFlags are forwarded to the window.
	//  - BeginPopupModal(): block every interaction behind the window, cannot be closed by user, add a dimming background, has a title bar.
	@(link_name="ImGui_BeginPopup")      BeginPopup      :: proc(str_id: cstring, flags: WindowFlags = {}) -> bool                    --- // return true if the popup is open, and you can start outputting to it.
	@(link_name="ImGui_BeginPopupModal") BeginPopupModal :: proc(name: cstring, p_open: ^bool = nil, flags: WindowFlags = {}) -> bool --- // return true if the modal is open, and you can start outputting to it.
	@(link_name="ImGui_EndPopup")        EndPopup        :: proc()                                                                    --- // only call EndPopup() if BeginPopupXXX() returns true!
	// Popups: open/close functions
	//  - OpenPopup(): set popup state to open. ImGuiPopupFlags are available for opening options.
	//  - If not modal: they can be closed by clicking anywhere outside them, or by pressing ESCAPE.
	//  - CloseCurrentPopup(): use inside the BeginPopup()/EndPopup() scope to close manually.
	//  - CloseCurrentPopup() is called by default by Selectable()/MenuItem() when activated (FIXME: need some options).
	//  - Use ImGuiPopupFlags_NoOpenOverExistingPopup to avoid opening a popup if there's already one at the same level. This is equivalent to e.g. testing for !IsAnyPopupOpen() prior to OpenPopup().
	//  - Use IsWindowAppearing() after BeginPopup() to tell if a window just opened.
	//  - IMPORTANT: Notice that for OpenPopupOnItemClick() we exceptionally default flags to 1 (== ImGuiPopupFlags_MouseButtonRight) for backward compatibility with older API taking 'int mouse_button = 1' parameter
	@(link_name="ImGui_OpenPopup")            OpenPopup            :: proc(str_id: cstring, popup_flags: PopupFlags = {})      --- // call to mark popup as open (don't call every frame!).
	@(link_name="ImGui_OpenPopupID")          OpenPopupID          :: proc(id: ID, popup_flags: PopupFlags = {})               --- // id overload to facilitate calling from nested stacks
	@(link_name="ImGui_OpenPopupOnItemClick") OpenPopupOnItemClick :: proc(str_id: cstring = nil, popup_flags: PopupFlags = 1) --- // helper to open popup when clicked on last item. Default to ImGuiPopupFlags_MouseButtonRight == 1. (note: actually triggers on the mouse _released_ event to be consistent with popup behaviors)
	@(link_name="ImGui_CloseCurrentPopup")    CloseCurrentPopup    :: proc()                                                   --- // manually close the popup we have begin-ed into.
	// Popups: open+begin combined functions helpers
	//  - Helpers to do OpenPopup+BeginPopup where the Open action is triggered by e.g. hovering an item and right-clicking.
	//  - They are convenient to easily create context menus, hence the name.
	//  - IMPORTANT: Notice that BeginPopupContextXXX takes ImGuiPopupFlags just like OpenPopup() and unlike BeginPopup(). For full consistency, we may add ImGuiWindowFlags to the BeginPopupContextXXX functions in the future.
	//  - IMPORTANT: Notice that we exceptionally default their flags to 1 (== ImGuiPopupFlags_MouseButtonRight) for backward compatibility with older API taking 'int mouse_button = 1' parameter, so if you add other flags remember to re-add the ImGuiPopupFlags_MouseButtonRight.
	@(link_name="ImGui_BeginPopupContextItem")   BeginPopupContextItem   :: proc(str_id: cstring = nil, popup_flags: PopupFlags = 1) -> bool --- // open+begin popup when clicked on last item. Use str_id==NULL to associate the popup to previous item. If you want to use that on a non-interactive item such as Text() you need to pass in an explicit ID here. read comments in .cpp!
	@(link_name="ImGui_BeginPopupContextWindow") BeginPopupContextWindow :: proc(str_id: cstring = nil, popup_flags: PopupFlags = 1) -> bool --- // open+begin popup when clicked on current window.
	@(link_name="ImGui_BeginPopupContextVoid")   BeginPopupContextVoid   :: proc(str_id: cstring = nil, popup_flags: PopupFlags = 1) -> bool --- // open+begin popup when clicked in void (where there are no windows).
	// Popups: query functions
	//  - IsPopupOpen(): return true if the popup is open at the current BeginPopup() level of the popup stack.
	//  - IsPopupOpen() with ImGuiPopupFlags_AnyPopupId: return true if any popup is open at the current BeginPopup() level of the popup stack.
	//  - IsPopupOpen() with ImGuiPopupFlags_AnyPopupId + ImGuiPopupFlags_AnyPopupLevel: return true if any popup is open.
	@(link_name="ImGui_IsPopupOpen") IsPopupOpen :: proc(str_id: cstring, flags: PopupFlags = {}) -> bool --- // return true if the popup is open.
	// Tables
	// - Full-featured replacement for old Columns API.
	// - See Demo->Tables for demo code. See top of imgui_tables.cpp for general commentary.
	// - See ImGuiTableFlags_ and ImGuiTableColumnFlags_ enums for a description of available flags.
	// The typical call flow is:
	// - 1. Call BeginTable(), early out if returning false.
	// - 2. Optionally call TableSetupColumn() to submit column name/flags/defaults.
	// - 3. Optionally call TableSetupScrollFreeze() to request scroll freezing of columns/rows.
	// - 4. Optionally call TableHeadersRow() to submit a header row. Names are pulled from TableSetupColumn() data.
	// - 5. Populate contents:
	//    - In most situations you can use TableNextRow() + TableSetColumnIndex(N) to start appending into a column.
	//    - If you are using tables as a sort of grid, where every column is holding the same type of contents,
	//      you may prefer using TableNextColumn() instead of TableNextRow() + TableSetColumnIndex().
	//      TableNextColumn() will automatically wrap-around into the next row if needed.
	//    - IMPORTANT: Comparatively to the old Columns() API, we need to call TableNextColumn() for the first column!
	//    - Summary of possible call flow:
	//        - TableNextRow() -> TableSetColumnIndex(0) -> Text("Hello 0") -> TableSetColumnIndex(1) -> Text("Hello 1")  // OK
	//        - TableNextRow() -> TableNextColumn()      -> Text("Hello 0") -> TableNextColumn()      -> Text("Hello 1")  // OK
	//        -                   TableNextColumn()      -> Text("Hello 0") -> TableNextColumn()      -> Text("Hello 1")  // OK: TableNextColumn() automatically gets to next row!
	//        - TableNextRow()                           -> Text("Hello 0")                                               // Not OK! Missing TableSetColumnIndex() or TableNextColumn()! Text will not appear!
	// - 5. Call EndTable()
	@(link_name="ImGui_BeginTable")          BeginTable          :: proc(str_id: cstring, columns: c.int, flags: TableFlags = {}, outer_size: Vec2 = {0.0, 0.0}, inner_width: f32 = 0.0) -> bool ---
	@(link_name="ImGui_EndTable")            EndTable            :: proc()                                                                                                                       --- // only call EndTable() if BeginTable() returns true!
	@(link_name="ImGui_TableNextRow")        TableNextRow        :: proc(row_flags: TableRowFlags = {}, min_row_height: f32 = 0.0)                                                               --- // append into the first cell of a new row.
	@(link_name="ImGui_TableNextColumn")     TableNextColumn     :: proc() -> bool                                                                                                               --- // append into the next column (or first column of next row if currently in last column). Return true when column is visible.
	@(link_name="ImGui_TableSetColumnIndex") TableSetColumnIndex :: proc(column_n: c.int) -> bool                                                                                                --- // append into the specified column. Return true when column is visible.
	// Tables: Headers & Columns declaration
	// - Use TableSetupColumn() to specify label, resizing policy, default width/weight, id, various other flags etc.
	// - Use TableHeadersRow() to create a header row and automatically submit a TableHeader() for each column.
	//   Headers are required to perform: reordering, sorting, and opening the context menu.
	//   The context menu can also be made available in columns body using ImGuiTableFlags_ContextMenuInBody.
	// - You may manually submit headers using TableNextRow() + TableHeader() calls, but this is only useful in
	//   some advanced use cases (e.g. adding custom widgets in header row).
	// - Use TableSetupScrollFreeze() to lock columns/rows so they stay visible when scrolled.
	@(link_name="ImGui_TableSetupColumn")       TableSetupColumn       :: proc(label: cstring, flags: TableColumnFlags = {}, init_width_or_weight: f32 = 0.0, user_id: ID = {}) ---
	@(link_name="ImGui_TableSetupScrollFreeze") TableSetupScrollFreeze :: proc(cols: c.int, rows: c.int)                                                                        --- // lock columns/rows so they stay visible when scrolled.
	@(link_name="ImGui_TableHeader")            TableHeader            :: proc(label: cstring)                                                                                  --- // submit one header cell manually (rarely used)
	@(link_name="ImGui_TableHeadersRow")        TableHeadersRow        :: proc()                                                                                                --- // submit a row with headers cells based on data provided to TableSetupColumn() + submit context menu
	@(link_name="ImGui_TableAngledHeadersRow")  TableAngledHeadersRow  :: proc()                                                                                                --- // submit a row with angled headers for every column with the ImGuiTableColumnFlags_AngledHeader flag. MUST BE FIRST ROW.
	// Tables: Sorting & Miscellaneous functions
	// - Sorting: call TableGetSortSpecs() to retrieve latest sort specs for the table. NULL when not sorting.
	//   When 'sort_specs->SpecsDirty == true' you should sort your data. It will be true when sorting specs have
	//   changed since last call, or the first time. Make sure to set 'SpecsDirty = false' after sorting,
	//   else you may wastefully sort your data every frame!
	// - Functions args 'int column_n' treat the default value of -1 as the same as passing the current column index.
	@(link_name="ImGui_TableGetSortSpecs")     TableGetSortSpecs     :: proc() -> ^TableSortSpecs                                     --- // get latest sort specs for the table (NULL if not sorting).  Lifetime: don't hold on this pointer over multiple frames or past any subsequent call to BeginTable().
	@(link_name="ImGui_TableGetColumnCount")   TableGetColumnCount   :: proc() -> c.int                                               --- // return number of columns (value passed to BeginTable)
	@(link_name="ImGui_TableGetColumnIndex")   TableGetColumnIndex   :: proc() -> c.int                                               --- // return current column index.
	@(link_name="ImGui_TableGetRowIndex")      TableGetRowIndex      :: proc() -> c.int                                               --- // return current row index.
	@(link_name="ImGui_TableGetColumnName")    TableGetColumnName    :: proc(column_n: c.int = -1) -> cstring                         --- // return "" if column didn't have a name declared by TableSetupColumn(). Pass -1 to use current column.
	@(link_name="ImGui_TableGetColumnFlags")   TableGetColumnFlags   :: proc(column_n: c.int = -1) -> TableColumnFlags                --- // return column flags so you can query their Enabled/Visible/Sorted/Hovered status flags. Pass -1 to use current column.
	@(link_name="ImGui_TableSetColumnEnabled") TableSetColumnEnabled :: proc(column_n: c.int, v: bool)                                --- // change user accessible enabled/disabled state of a column. Set to false to hide the column. User can use the context menu to change this themselves (right-click in headers, or right-click in columns body with ImGuiTableFlags_ContextMenuInBody)
	@(link_name="ImGui_TableGetHoveredColumn") TableGetHoveredColumn :: proc() -> c.int                                               --- // return hovered column. return -1 when table is not hovered. return columns_count if the unused space at the right of visible columns is hovered. Can also use (TableGetColumnFlags() & ImGuiTableColumnFlags_IsHovered) instead.
	@(link_name="ImGui_TableSetBgColor")       TableSetBgColor       :: proc(target: TableBgTarget, color: u32, column_n: c.int = -1) --- // change the color of a cell, row, or column. See ImGuiTableBgTarget_ flags for details.
	// Legacy Columns API (prefer using Tables!)
	// - You can also use SameLine(pos_x) to mimic simplified columns.
	@(link_name="ImGui_Columns")         Columns         :: proc(count: c.int = 1, id: cstring = nil, borders: bool = true) ---
	@(link_name="ImGui_NextColumn")      NextColumn      :: proc()                                                          --- // next column, defaults to current row or next row if the current row is finished
	@(link_name="ImGui_GetColumnIndex")  GetColumnIndex  :: proc() -> c.int                                                 --- // get current column index
	@(link_name="ImGui_GetColumnWidth")  GetColumnWidth  :: proc(column_index: c.int = -1) -> f32                           --- // get column width (in pixels). pass -1 to use current column
	@(link_name="ImGui_SetColumnWidth")  SetColumnWidth  :: proc(column_index: c.int, width: f32)                           --- // set column width (in pixels). pass -1 to use current column
	@(link_name="ImGui_GetColumnOffset") GetColumnOffset :: proc(column_index: c.int = -1) -> f32                           --- // get position of column line (in pixels, from the left side of the contents region). pass -1 to use current column, otherwise 0..GetColumnsCount() inclusive. column 0 is typically 0.0f
	@(link_name="ImGui_SetColumnOffset") SetColumnOffset :: proc(column_index: c.int, offset_x: f32)                        --- // set position of column line (in pixels, from the left side of the contents region). pass -1 to use current column
	@(link_name="ImGui_GetColumnsCount") GetColumnsCount :: proc() -> c.int                                                 ---
	// Tab Bars, Tabs
	// - Note: Tabs are automatically created by the docking system (when in 'docking' branch). Use this to create tab bars/tabs yourself.
	@(link_name="ImGui_BeginTabBar")      BeginTabBar      :: proc(str_id: cstring, flags: TabBarFlags = {}) -> bool                      --- // create and append into a TabBar
	@(link_name="ImGui_EndTabBar")        EndTabBar        :: proc()                                                                      --- // only call EndTabBar() if BeginTabBar() returns true!
	@(link_name="ImGui_BeginTabItem")     BeginTabItem     :: proc(label: cstring, p_open: ^bool = nil, flags: TabItemFlags = {}) -> bool --- // create a Tab. Returns true if the Tab is selected.
	@(link_name="ImGui_EndTabItem")       EndTabItem       :: proc()                                                                      --- // only call EndTabItem() if BeginTabItem() returns true!
	@(link_name="ImGui_TabItemButton")    TabItemButton    :: proc(label: cstring, flags: TabItemFlags = {}) -> bool                      --- // create a Tab behaving like a button. return true when clicked. cannot be selected in the tab bar.
	@(link_name="ImGui_SetTabItemClosed") SetTabItemClosed :: proc(tab_or_docked_window_label: cstring)                                   --- // notify TabBar or Docking system of a closed tab/window ahead (useful to reduce visual flicker on reorderable tab bars). For tab-bar: call after BeginTabBar() and before Tab submissions. Otherwise call with a window name.
	// Docking
	// [BETA API] Enable with io.ConfigFlags |= ImGuiConfigFlags_DockingEnable.
	// Note: You can use most Docking facilities without calling any API. You DO NOT need to call DockSpace() to use Docking!
	// - Drag from window title bar or their tab to dock/undock. Hold SHIFT to disable docking.
	// - Drag from window menu button (upper-left button) to undock an entire node (all windows).
	// - When io.ConfigDockingWithShift == true, you instead need to hold SHIFT to enable docking.
	// About dockspaces:
	// - Use DockSpaceOverViewport() to create a window covering the screen or a specific viewport + a dockspace inside it.
	//   This is often used with ImGuiDockNodeFlags_PassthruCentralNode to make it transparent.
	// - Use DockSpace() to create an explicit dock node _within_ an existing window. See Docking demo for details.
	// - Important: Dockspaces need to be submitted _before_ any window they can host. Submit it early in your frame!
	// - Important: Dockspaces need to be kept alive if hidden, otherwise windows docked into it will be undocked.
	//   e.g. if you have multiple tabs with a dockspace inside each tab: submit the non-visible dockspaces with ImGuiDockNodeFlags_KeepAliveOnly.
	@(link_name="ImGui_DockSpace")             DockSpace             :: proc(dockspace_id: ID, size: Vec2 = {0, 0}, flags: DockNodeFlags = {}, window_class: ^WindowClass = nil) -> ID            ---
	@(link_name="ImGui_DockSpaceOverViewport") DockSpaceOverViewport :: proc(dockspace_id: ID = {}, viewport: ^Viewport = nil, flags: DockNodeFlags = {}, window_class: ^WindowClass = nil) -> ID ---
	@(link_name="ImGui_SetNextWindowDockID")   SetNextWindowDockID   :: proc(dock_id: ID, cond: Cond = {})                                                                                        --- // set next window dock id
	@(link_name="ImGui_SetNextWindowClass")    SetNextWindowClass    :: proc(window_class: ^WindowClass)                                                                                          --- // set next window class (control docking compatibility + provide hints to platform backend via custom viewport flags and platform parent/child relationship)
	@(link_name="ImGui_GetWindowDockID")       GetWindowDockID       :: proc() -> ID                                                                                                              ---
	@(link_name="ImGui_IsWindowDocked")        IsWindowDocked        :: proc() -> bool                                                                                                            --- // is current window docked into another window?
	// Logging/Capture
	// - All text output from the interface can be captured into tty/file/clipboard. By default, tree nodes are automatically opened during logging.
	@(link_name="ImGui_LogToTTY")       LogToTTY       :: proc(auto_open_depth: c.int = -1)                          --- // start logging to tty (stdout)
	@(link_name="ImGui_LogToFile")      LogToFile      :: proc(auto_open_depth: c.int = -1, filename: cstring = nil) --- // start logging to file
	@(link_name="ImGui_LogToClipboard") LogToClipboard :: proc(auto_open_depth: c.int = -1)                          --- // start logging to OS clipboard
	@(link_name="ImGui_LogFinish")      LogFinish      :: proc()                                                     --- // stop logging (close file, etc.)
	@(link_name="ImGui_LogButtons")     LogButtons     :: proc()                                                     --- // helper to display buttons for logging to tty/file/clipboard
	@(link_name="ImGui_LogText")        LogText        :: proc(fmt: cstring, #c_vararg args: ..any)                  --- // pass text data straight to log (without being displayed)
	// Drag and Drop
	// - On source items, call BeginDragDropSource(), if it returns true also call SetDragDropPayload() + EndDragDropSource().
	// - On target candidates, call BeginDragDropTarget(), if it returns true also call AcceptDragDropPayload() + EndDragDropTarget().
	// - If you stop calling BeginDragDropSource() the payload is preserved however it won't have a preview tooltip (we currently display a fallback "..." tooltip, see #1725)
	// - An item can be both drag source and drop target.
	@(link_name="ImGui_BeginDragDropSource")   BeginDragDropSource   :: proc(flags: DragDropFlags = {}) -> bool                                  --- // call after submitting an item which may be dragged. when this return true, you can call SetDragDropPayload() + EndDragDropSource()
	@(link_name="ImGui_SetDragDropPayload")    SetDragDropPayload    :: proc(type: cstring, data: rawptr, sz: c.size_t, cond: Cond = {}) -> bool --- // type is a user defined string of maximum 32 characters. Strings starting with '_' are reserved for dear imgui internal types. Data is copied and held by imgui. Return true when payload has been accepted.
	@(link_name="ImGui_EndDragDropSource")     EndDragDropSource     :: proc()                                                                   --- // only call EndDragDropSource() if BeginDragDropSource() returns true!
	@(link_name="ImGui_BeginDragDropTarget")   BeginDragDropTarget   :: proc() -> bool                                                           --- // call after submitting an item that may receive a payload. If this returns true, you can call AcceptDragDropPayload() + EndDragDropTarget()
	@(link_name="ImGui_AcceptDragDropPayload") AcceptDragDropPayload :: proc(type: cstring, flags: DragDropFlags = {}) -> ^Payload               --- // accept contents of a given type. If ImGuiDragDropFlags_AcceptBeforeDelivery is set you can peek into the payload before the mouse button is released.
	@(link_name="ImGui_EndDragDropTarget")     EndDragDropTarget     :: proc()                                                                   --- // only call EndDragDropTarget() if BeginDragDropTarget() returns true!
	@(link_name="ImGui_GetDragDropPayload")    GetDragDropPayload    :: proc() -> ^Payload                                                       --- // peek directly into the current payload from anywhere. returns NULL when drag and drop is finished or inactive. use ImGuiPayload::IsDataType() to test for the payload type.
	// Disabling [BETA API]
	// - Disable all user interactions and dim items visuals (applying style.DisabledAlpha over current colors)
	// - Those can be nested but it cannot be used to enable an already disabled section (a single BeginDisabled(true) in the stack is enough to keep everything disabled)
	// - Tooltips windows by exception are opted out of disabling.
	// - BeginDisabled(false)/EndDisabled() essentially does nothing but is provided to facilitate use of boolean expressions (as a micro-optimization: if you have tens of thousands of BeginDisabled(false)/EndDisabled() pairs, you might want to reformulate your code to avoid making those calls)
	@(link_name="ImGui_BeginDisabled") BeginDisabled :: proc(disabled: bool = true) ---
	@(link_name="ImGui_EndDisabled")   EndDisabled   :: proc()                      ---
	// Clipping
	// - Mouse hovering is affected by ImGui::PushClipRect() calls, unlike direct calls to ImDrawList::PushClipRect() which are render only.
	@(link_name="ImGui_PushClipRect") PushClipRect :: proc(clip_rect_min: Vec2, clip_rect_max: Vec2, intersect_with_current_clip_rect: bool) ---
	@(link_name="ImGui_PopClipRect")  PopClipRect  :: proc()                                                                                 ---
	// Focus, Activation
	@(link_name="ImGui_SetItemDefaultFocus")  SetItemDefaultFocus  :: proc()                   --- // make last item the default focused item of of a newly appearing window.
	@(link_name="ImGui_SetKeyboardFocusHere") SetKeyboardFocusHere :: proc(offset: c.int = {}) --- // focus keyboard on the next widget. Use positive 'offset' to access sub components of a multiple component widget. Use -1 to access previous widget.
	// Keyboard/Gamepad Navigation
	@(link_name="ImGui_SetNavCursorVisible") SetNavCursorVisible :: proc(visible: bool) --- // alter visibility of keyboard/gamepad cursor. by default: show when using an arrow key, hide when clicking with mouse.
	// Overlapping mode
	@(link_name="ImGui_SetNextItemAllowOverlap") SetNextItemAllowOverlap :: proc() --- // allow next item to be overlapped by a subsequent item. Useful with invisible buttons, selectable, treenode covering an area where subsequent items may need to be added. Note that both Selectable() and TreeNode() have dedicated flags doing this.
	// Item/Widgets Utilities and Query Functions
	// - Most of the functions are referring to the previous Item that has been submitted.
	// - See Demo Window under "Widgets->Querying Status" for an interactive visualization of most of those functions.
	@(link_name="ImGui_IsItemHovered")              IsItemHovered              :: proc(flags: HoveredFlags = {}) -> bool       --- // is the last item hovered? (and usable, aka not blocked by a popup, etc.). See ImGuiHoveredFlags for more options.
	@(link_name="ImGui_IsItemActive")               IsItemActive               :: proc() -> bool                               --- // is the last item active? (e.g. button being held, text field being edited. This will continuously return true while holding mouse button on an item. Items that don't interact will always return false)
	@(link_name="ImGui_IsItemFocused")              IsItemFocused              :: proc() -> bool                               --- // is the last item focused for keyboard/gamepad navigation?
	@(link_name="ImGui_IsItemClicked")              IsItemClicked              :: proc(mouse_button: MouseButton = {}) -> bool --- // is the last item hovered and mouse clicked on? (**)  == IsMouseClicked(mouse_button) && IsItemHovered()Important. (**) this is NOT equivalent to the behavior of e.g. Button(). Read comments in function definition.
	@(link_name="ImGui_IsItemVisible")              IsItemVisible              :: proc() -> bool                               --- // is the last item visible? (items may be out of sight because of clipping/scrolling)
	@(link_name="ImGui_IsItemEdited")               IsItemEdited               :: proc() -> bool                               --- // did the last item modify its underlying value this frame? or was pressed? This is generally the same as the "bool" return value of many widgets.
	@(link_name="ImGui_IsItemActivated")            IsItemActivated            :: proc() -> bool                               --- // was the last item just made active (item was previously inactive).
	@(link_name="ImGui_IsItemDeactivated")          IsItemDeactivated          :: proc() -> bool                               --- // was the last item just made inactive (item was previously active). Useful for Undo/Redo patterns with widgets that require continuous editing.
	@(link_name="ImGui_IsItemDeactivatedAfterEdit") IsItemDeactivatedAfterEdit :: proc() -> bool                               --- // was the last item just made inactive and made a value change when it was active? (e.g. Slider/Drag moved). Useful for Undo/Redo patterns with widgets that require continuous editing. Note that you may get false positives (some widgets such as Combo()/ListBox()/Selectable() will return true even when clicking an already selected item).
	@(link_name="ImGui_IsItemToggledOpen")          IsItemToggledOpen          :: proc() -> bool                               --- // was the last item open state toggled? set by TreeNode().
	@(link_name="ImGui_IsAnyItemHovered")           IsAnyItemHovered           :: proc() -> bool                               --- // is any item hovered?
	@(link_name="ImGui_IsAnyItemActive")            IsAnyItemActive            :: proc() -> bool                               --- // is any item active?
	@(link_name="ImGui_IsAnyItemFocused")           IsAnyItemFocused           :: proc() -> bool                               --- // is any item focused?
	@(link_name="ImGui_GetItemID")                  GetItemID                  :: proc() -> ID                                 --- // get ID of last item (~~ often same ImGui::GetID(label) beforehand)
	@(link_name="ImGui_GetItemRectMin")             GetItemRectMin             :: proc() -> Vec2                               --- // get upper-left bounding rectangle of the last item (screen space)
	@(link_name="ImGui_GetItemRectMax")             GetItemRectMax             :: proc() -> Vec2                               --- // get lower-right bounding rectangle of the last item (screen space)
	@(link_name="ImGui_GetItemRectSize")            GetItemRectSize            :: proc() -> Vec2                               --- // get size of last item
	// Viewports
	// - Currently represents the Platform Window created by the application which is hosting our Dear ImGui windows.
	// - In 'docking' branch with multi-viewport enabled, we extend this concept to have multiple active viewports.
	// - In the future we will extend this concept further to also represent Platform Monitor and support a "no main platform window" operation mode.
	@(link_name="ImGui_GetMainViewport") GetMainViewport :: proc() -> ^Viewport --- // return primary/default viewport. This can never be NULL.
	// Background/Foreground Draw Lists
	@(link_name="ImGui_GetBackgroundDrawList") GetBackgroundDrawList :: proc(viewport: ^Viewport = nil) -> ^DrawList --- // get background draw list for the given viewport or viewport associated to the current window. this draw list will be the first rendering one. Useful to quickly draw shapes/text behind dear imgui contents.
	@(link_name="ImGui_GetForegroundDrawList") GetForegroundDrawList :: proc(viewport: ^Viewport = nil) -> ^DrawList --- // get foreground draw list for the given viewport or viewport associated to the current window. this draw list will be the top-most rendered one. Useful to quickly draw shapes/text over dear imgui contents.
	// Miscellaneous Utilities
	@(link_name="ImGui_IsRectVisibleBySize")   IsRectVisibleBySize   :: proc(size: Vec2) -> bool                     --- // test if rectangle (of given size, starting from cursor position) is visible / not clipped.
	@(link_name="ImGui_IsRectVisible")         IsRectVisible         :: proc(rect_min: Vec2, rect_max: Vec2) -> bool --- // test if rectangle (in screen space) is visible / not clipped. to perform coarse clipping on user's side.
	@(link_name="ImGui_GetTime")               GetTime               :: proc() -> f64                                --- // get global imgui time. incremented by io.DeltaTime every frame.
	@(link_name="ImGui_GetFrameCount")         GetFrameCount         :: proc() -> c.int                              --- // get global imgui frame count. incremented by 1 every frame.
	@(link_name="ImGui_GetDrawListSharedData") GetDrawListSharedData :: proc() -> ^DrawListSharedData                --- // you may use this when creating your own ImDrawList instances.
	@(link_name="ImGui_GetStyleColorName")     GetStyleColorName     :: proc(idx: Col) -> cstring                    --- // get a string corresponding to the enum value (for display, saving, etc.).
	@(link_name="ImGui_SetStateStorage")       SetStateStorage       :: proc(storage: ^Storage)                      --- // replace current window storage with our own (if you want to manipulate it yourself, typically clear subsection of it)
	@(link_name="ImGui_GetStateStorage")       GetStateStorage       :: proc() -> ^Storage                           ---
	// Text Utilities
	@(link_name="ImGui_CalcTextSize") CalcTextSize :: proc(text: cstring, text_end: cstring = nil, hide_text_after_double_hash: bool = false, wrap_width: f32 = -1.0) -> Vec2 ---
	// Color Utilities
	@(link_name="ImGui_ColorConvertU32ToFloat4") ColorConvertU32ToFloat4 :: proc(_in: u32) -> Vec4                                              ---
	@(link_name="ImGui_ColorConvertFloat4ToU32") ColorConvertFloat4ToU32 :: proc(_in: Vec4) -> u32                                              ---
	@(link_name="ImGui_ColorConvertRGBtoHSV")    ColorConvertRGBtoHSV    :: proc(r: f32, g: f32, b: f32, out_h: ^f32, out_s: ^f32, out_v: ^f32) ---
	@(link_name="ImGui_ColorConvertHSVtoRGB")    ColorConvertHSVtoRGB    :: proc(h: f32, s: f32, v: f32, out_r: ^f32, out_g: ^f32, out_b: ^f32) ---
	// Inputs Utilities: Keyboard/Mouse/Gamepad
	// - the ImGuiKey enum contains all possible keyboard, mouse and gamepad inputs (e.g. ImGuiKey_A, ImGuiKey_MouseLeft, ImGuiKey_GamepadDpadUp...).
	// - (legacy: before v1.87, we used ImGuiKey to carry native/user indices as defined by each backends. This was obsoleted in 1.87 (2022-02) and completely removed in 1.91.5 (2024-11). See https://github.com/ocornut/imgui/issues/4921)
	// - (legacy: any use of ImGuiKey will assert when key < 512 to detect passing legacy native/user indices)
	@(link_name="ImGui_IsKeyDown")                       IsKeyDown                       :: proc(key: Key) -> bool                                --- // is key being held.
	@(link_name="ImGui_IsKeyPressed")                    IsKeyPressed                    :: proc(key: Key, repeat: bool = true) -> bool           --- // was key pressed (went from !Down to Down)? if repeat=true, uses io.KeyRepeatDelay / KeyRepeatRate
	@(link_name="ImGui_IsKeyReleased")                   IsKeyReleased                   :: proc(key: Key) -> bool                                --- // was key released (went from Down to !Down)?
	@(link_name="ImGui_IsKeyChordPressed")               IsKeyChordPressed               :: proc(key_chord: KeyChord) -> bool                     --- // was key chord (mods + key) pressed, e.g. you can pass 'ImGuiMod_Ctrl | ImGuiKey_S' as a key-chord. This doesn't do any routing or focus check, please consider using Shortcut() function instead.
	@(link_name="ImGui_GetKeyPressedAmount")             GetKeyPressedAmount             :: proc(key: Key, repeat_delay: f32, rate: f32) -> c.int --- // uses provided repeat rate/delay. return a count, most often 0 or 1 but might be >1 if RepeatRate is small enough that DeltaTime > RepeatRate
	@(link_name="ImGui_GetKeyName")                      GetKeyName                      :: proc(key: Key) -> cstring                             --- // [DEBUG] returns English name of the key. Those names a provided for debugging purpose and are not meant to be saved persistently not compared.
	@(link_name="ImGui_SetNextFrameWantCaptureKeyboard") SetNextFrameWantCaptureKeyboard :: proc(want_capture_keyboard: bool)                     --- // Override io.WantCaptureKeyboard flag next frame (said flag is left for your application to handle, typically when true it instructs your app to ignore inputs). e.g. force capture keyboard when your widget is being hovered. This is equivalent to setting "io.WantCaptureKeyboard = want_capture_keyboard"; after the next NewFrame() call.
	// Inputs Utilities: Shortcut Testing & Routing [BETA]
	// - ImGuiKeyChord = a ImGuiKey + optional ImGuiMod_Alt/ImGuiMod_Ctrl/ImGuiMod_Shift/ImGuiMod_Super.
	//       ImGuiKey_C                          // Accepted by functions taking ImGuiKey or ImGuiKeyChord arguments)
	//       ImGuiMod_Ctrl | ImGuiKey_C          // Accepted by functions taking ImGuiKeyChord arguments)
	//   only ImGuiMod_XXX values are legal to combine with an ImGuiKey. You CANNOT combine two ImGuiKey values.
	// - The general idea is that several callers may register interest in a shortcut, and only one owner gets it.
	//      Parent   -> call Shortcut(Ctrl+S)    // When Parent is focused, Parent gets the shortcut.
	//        Child1 -> call Shortcut(Ctrl+S)    // When Child1 is focused, Child1 gets the shortcut (Child1 overrides Parent shortcuts)
	//        Child2 -> no call                  // When Child2 is focused, Parent gets the shortcut.
	//   The whole system is order independent, so if Child1 makes its calls before Parent, results will be identical.
	//   This is an important property as it facilitate working with foreign code or larger codebase.
	// - To understand the difference:
	//   - IsKeyChordPressed() compares mods and call IsKeyPressed() -> function has no side-effect.
	//   - Shortcut() submits a route, routes are resolved, if it currently can be routed it calls IsKeyChordPressed() -> function has (desirable) side-effects as it can prevents another call from getting the route.
	// - Visualize registered routes in 'Metrics/Debugger->Inputs'.
	@(link_name="ImGui_Shortcut")            Shortcut            :: proc(key_chord: KeyChord, flags: InputFlags = {}) -> bool ---
	@(link_name="ImGui_SetNextItemShortcut") SetNextItemShortcut :: proc(key_chord: KeyChord, flags: InputFlags = {})         ---
	// Inputs Utilities: Key/Input Ownership [BETA]
	// - One common use case would be to allow your items to disable standard inputs behaviors such
	//   as Tab or Alt key handling, Mouse Wheel scrolling, etc.
	//   e.g. Button(...); SetItemKeyOwner(ImGuiKey_MouseWheelY); to make hovering/activating a button disable wheel for scrolling.
	// - Reminder ImGuiKey enum include access to mouse buttons and gamepad, so key ownership can apply to them.
	// - Many related features are still in imgui_internal.h. For instance, most IsKeyXXX()/IsMouseXXX() functions have an owner-id-aware version.
	@(link_name="ImGui_SetItemKeyOwner") SetItemKeyOwner :: proc(key: Key) --- // Set key owner to last item ID if it is hovered or active. Equivalent to 'if (IsItemHovered() || IsItemActive()) { SetKeyOwner(key, GetItemID());'.
	// Inputs Utilities: Mouse
	// - To refer to a mouse button, you may use named enums in your code e.g. ImGuiMouseButton_Left, ImGuiMouseButton_Right.
	// - You can also use regular integer: it is forever guaranteed that 0=Left, 1=Right, 2=Middle.
	// - Dragging operations are only reported after mouse has moved a certain distance away from the initial clicking position (see 'lock_threshold' and 'io.MouseDraggingThreshold')
	@(link_name="ImGui_IsMouseDown")                      IsMouseDown                      :: proc(button: MouseButton) -> bool                                  --- // is mouse button held?
	@(link_name="ImGui_IsMouseClicked")                   IsMouseClicked                   :: proc(button: MouseButton, repeat: bool = false) -> bool            --- // did mouse button clicked? (went from !Down to Down). Same as GetMouseClickedCount() == 1.
	@(link_name="ImGui_IsMouseReleased")                  IsMouseReleased                  :: proc(button: MouseButton) -> bool                                  --- // did mouse button released? (went from Down to !Down)
	@(link_name="ImGui_IsMouseDoubleClicked")             IsMouseDoubleClicked             :: proc(button: MouseButton) -> bool                                  --- // did mouse button double-clicked? Same as GetMouseClickedCount() == 2. (note that a double-click will also report IsMouseClicked() == true)
	@(link_name="ImGui_GetMouseClickedCount")             GetMouseClickedCount             :: proc(button: MouseButton) -> c.int                                 --- // return the number of successive mouse-clicks at the time where a click happen (otherwise 0).
	@(link_name="ImGui_IsMouseHoveringRect")              IsMouseHoveringRect              :: proc(r_min: Vec2, r_max: Vec2, clip: bool = true) -> bool          --- // is mouse hovering given bounding rect (in screen space). clipped by current clipping settings, but disregarding of other consideration of focus/window ordering/popup-block.
	@(link_name="ImGui_IsMousePosValid")                  IsMousePosValid                  :: proc(mouse_pos: ^Vec2 = nil) -> bool                               --- // by convention we use (-FLT_MAX,-FLT_MAX) to denote that there is no mouse available
	@(link_name="ImGui_IsAnyMouseDown")                   IsAnyMouseDown                   :: proc() -> bool                                                     --- // [WILL OBSOLETE] is any mouse button held? This was designed for backends, but prefer having backend maintain a mask of held mouse buttons, because upcoming input queue system will make this invalid.
	@(link_name="ImGui_GetMousePos")                      GetMousePos                      :: proc() -> Vec2                                                     --- // shortcut to ImGui::GetIO().MousePos provided by user, to be consistent with other calls
	@(link_name="ImGui_GetMousePosOnOpeningCurrentPopup") GetMousePosOnOpeningCurrentPopup :: proc() -> Vec2                                                     --- // retrieve mouse position at the time of opening popup we have BeginPopup() into (helper to avoid user backing that value themselves)
	@(link_name="ImGui_IsMouseDragging")                  IsMouseDragging                  :: proc(button: MouseButton, lock_threshold: f32 = -1.0) -> bool      --- // is mouse dragging? (uses io.MouseDraggingThreshold if lock_threshold < 0.0f)
	@(link_name="ImGui_GetMouseDragDelta")                GetMouseDragDelta                :: proc(button: MouseButton = {}, lock_threshold: f32 = -1.0) -> Vec2 --- // return the delta from the initial clicking position while the mouse button is pressed or was just released. This is locked and return 0.0f until the mouse moves past a distance threshold at least once (uses io.MouseDraggingThreshold if lock_threshold < 0.0f)
	@(link_name="ImGui_ResetMouseDragDelta")              ResetMouseDragDelta              :: proc(button: MouseButton = {})                                     --- //
	@(link_name="ImGui_GetMouseCursor")                   GetMouseCursor                   :: proc() -> MouseCursor                                              --- // get desired mouse cursor shape. Important: reset in ImGui::NewFrame(), this is updated during the frame. valid before Render(). If you use software rendering by setting io.MouseDrawCursor ImGui will render those for you
	@(link_name="ImGui_SetMouseCursor")                   SetMouseCursor                   :: proc(cursor_type: MouseCursor)                                     --- // set desired mouse cursor shape
	@(link_name="ImGui_SetNextFrameWantCaptureMouse")     SetNextFrameWantCaptureMouse     :: proc(want_capture_mouse: bool)                                     --- // Override io.WantCaptureMouse flag next frame (said flag is left for your application to handle, typical when true it instucts your app to ignore inputs). This is equivalent to setting "io.WantCaptureMouse = want_capture_mouse;" after the next NewFrame() call.
	// Clipboard Utilities
	// - Also see the LogToClipboard() function to capture GUI into clipboard, or easily output text data to the clipboard.
	@(link_name="ImGui_GetClipboardText") GetClipboardText :: proc() -> cstring   ---
	@(link_name="ImGui_SetClipboardText") SetClipboardText :: proc(text: cstring) ---
	// Settings/.Ini Utilities
	// - The disk functions are automatically called if io.IniFilename != NULL (default is "imgui.ini").
	// - Set io.IniFilename to NULL to load/save manually. Read io.WantSaveIniSettings description about handling .ini saving manually.
	// - Important: default value "imgui.ini" is relative to current working dir! Most apps will want to lock this to an absolute path (e.g. same path as executables).
	@(link_name="ImGui_LoadIniSettingsFromDisk")   LoadIniSettingsFromDisk   :: proc(ini_filename: cstring)                      --- // call after CreateContext() and before the first call to NewFrame(). NewFrame() automatically calls LoadIniSettingsFromDisk(io.IniFilename).
	@(link_name="ImGui_LoadIniSettingsFromMemory") LoadIniSettingsFromMemory :: proc(ini_data: cstring, ini_size: c.size_t = {}) --- // call after CreateContext() and before the first call to NewFrame() to provide .ini data from your own data source.
	@(link_name="ImGui_SaveIniSettingsToDisk")     SaveIniSettingsToDisk     :: proc(ini_filename: cstring)                      --- // this is automatically called (if io.IniFilename is not empty) a few seconds after any modification that should be reflected in the .ini file (and also by DestroyContext).
	@(link_name="ImGui_SaveIniSettingsToMemory")   SaveIniSettingsToMemory   :: proc(out_ini_size: ^c.size_t = nil) -> cstring   --- // return a zero-terminated string with the .ini data which you can save by your own mean. call when io.WantSaveIniSettings is set, then save data by your own mean and clear io.WantSaveIniSettings.
	// Debug Utilities
	// - Your main debugging friend is the ShowMetricsWindow() function, which is also accessible from Demo->Tools->Metrics Debugger
	@(link_name="ImGui_DebugTextEncoding")              DebugTextEncoding              :: proc(text: cstring)                                                                                                                                        ---
	@(link_name="ImGui_DebugFlashStyleColor")           DebugFlashStyleColor           :: proc(idx: Col)                                                                                                                                             ---
	@(link_name="ImGui_DebugStartItemPicker")           DebugStartItemPicker           :: proc()                                                                                                                                                     ---
	@(link_name="ImGui_DebugCheckVersionAndDataLayout") DebugCheckVersionAndDataLayout :: proc(version_str: cstring, sz_io: c.size_t, sz_style: c.size_t, sz_vec2: c.size_t, sz_vec4: c.size_t, sz_drawvert: c.size_t, sz_drawidx: c.size_t) -> bool --- // This is called by IMGUI_CHECKVERSION() macro.
	@(link_name="ImGui_DebugLog")                       DebugLog                       :: proc(fmt: cstring, #c_vararg args: ..any)                                                                                                                  --- // Call via IMGUI_DEBUG_LOG() for maximum stripping in caller code!
	// Memory Allocators
	// - Those functions are not reliant on the current context.
	// - DLL users: heaps and globals are not shared across DLL boundaries! You will need to call SetCurrentContext() + SetAllocatorFunctions()
	//   for each static/DLL boundary you are calling from. Read "Context and Memory Allocators" section of imgui.cpp for more details.
	@(link_name="ImGui_SetAllocatorFunctions") SetAllocatorFunctions :: proc(alloc_func: MemAllocFunc, free_func: MemFreeFunc, user_data: rawptr = nil)    ---
	@(link_name="ImGui_GetAllocatorFunctions") GetAllocatorFunctions :: proc(p_alloc_func: ^MemAllocFunc, p_free_func: ^MemFreeFunc, p_user_data: ^rawptr) ---
	@(link_name="ImGui_MemAlloc")              MemAlloc              :: proc(size: c.size_t) -> rawptr                                                     ---
	@(link_name="ImGui_MemFree")               MemFree               :: proc(ptr: rawptr)                                                                  ---
	// (Optional) Platform/OS interface for multi-viewport support
	// Read comments around the ImGuiPlatformIO structure for more details.
	// Note: You may use GetWindowViewport() to get the current viewport of the current window.
	@(link_name="ImGui_UpdatePlatformWindows")        UpdatePlatformWindows        :: proc()                                                                     --- // call in main loop. will call CreateWindow/ResizeWindow/etc. platform functions for each secondary viewport, and DestroyWindow for each inactive viewport.
	@(link_name="ImGui_RenderPlatformWindowsDefault") RenderPlatformWindowsDefault :: proc(platform_render_arg: rawptr = nil, renderer_render_arg: rawptr = nil) --- // call in main loop. will call RenderWindow/SwapBuffers platform functions for each secondary viewport which doesn't have the ImGuiViewportFlags_Minimized flag set. May be reimplemented by user for custom rendering needs.
	@(link_name="ImGui_DestroyPlatformWindows")       DestroyPlatformWindows       :: proc()                                                                     --- // call DestroyWindow platform functions for all viewports. call from backend Shutdown() if you need to close platform windows before imgui shutdown. otherwise will be called by DestroyContext().
	@(link_name="ImGui_FindViewportByID")             FindViewportByID             :: proc(id: ID) -> ^Viewport                                                  --- // this is a helper for backends.
	@(link_name="ImGui_FindViewportByPlatformHandle") FindViewportByPlatformHandle :: proc(platform_handle: rawptr) -> ^Viewport                                 --- // this is a helper for backends. the type platform_handle is decided by the backend (e.g. HWND, MyWindow*, GLFWwindow* etc.)
	@(link_name="ImVector_Construct")                 Vector_Construct             :: proc(vector: rawptr)                                                       --- // Construct a zero-size ImVector<> (of any type). This is primarily useful when calling ImFontGlyphRangesBuilder_BuildRanges()
	@(link_name="ImVector_Destruct")                  Vector_Destruct              :: proc(vector: rawptr)                                                       --- // Destruct an ImVector<> (of any type). Important: Frees the vector memory but does not call destructors on contained objects (if they have them)
	@(link_name="ImGuiStyle_ScaleAllSizes")           Style_ScaleAllSizes          :: proc(self: ^Style, scale_factor: f32)                                      ---
	// Input Functions
	@(link_name="ImGuiIO_AddKeyEvent")                       IO_AddKeyEvent                       :: proc(self: ^IO, key: Key, down: bool)                                                                     --- // Queue a new key down/up event. Key should be "translated" (as in, generally ImGuiKey_A matches the key end-user would use to emit an 'A' character)
	@(link_name="ImGuiIO_AddKeyAnalogEvent")                 IO_AddKeyAnalogEvent                 :: proc(self: ^IO, key: Key, down: bool, v: f32)                                                             --- // Queue a new key down/up event for analog values (e.g. ImGuiKey_Gamepad_ values). Dead-zones should be handled by the backend.
	@(link_name="ImGuiIO_AddMousePosEvent")                  IO_AddMousePosEvent                  :: proc(self: ^IO, x: f32, y: f32)                                                                           --- // Queue a mouse position update. Use -FLT_MAX,-FLT_MAX to signify no mouse (e.g. app not focused and not hovered)
	@(link_name="ImGuiIO_AddMouseButtonEvent")               IO_AddMouseButtonEvent               :: proc(self: ^IO, button: c.int, down: bool)                                                                --- // Queue a mouse button change
	@(link_name="ImGuiIO_AddMouseWheelEvent")                IO_AddMouseWheelEvent                :: proc(self: ^IO, wheel_x: f32, wheel_y: f32)                                                               --- // Queue a mouse wheel update. wheel_y<0: scroll down, wheel_y>0: scroll up, wheel_x<0: scroll right, wheel_x>0: scroll left.
	@(link_name="ImGuiIO_AddMouseSourceEvent")               IO_AddMouseSourceEvent               :: proc(self: ^IO, source: MouseSource)                                                                      --- // Queue a mouse source change (Mouse/TouchScreen/Pen)
	@(link_name="ImGuiIO_AddMouseViewportEvent")             IO_AddMouseViewportEvent             :: proc(self: ^IO, id: ID)                                                                                   --- // Queue a mouse hovered viewport. Requires backend to set ImGuiBackendFlags_HasMouseHoveredViewport to call this (for multi-viewport support).
	@(link_name="ImGuiIO_AddFocusEvent")                     IO_AddFocusEvent                     :: proc(self: ^IO, focused: bool)                                                                            --- // Queue a gain/loss of focus for the application (generally based on OS/platform focus of your window)
	@(link_name="ImGuiIO_AddInputCharacter")                 IO_AddInputCharacter                 :: proc(self: ^IO, _c: c.uint)                                                                               --- // Queue a new character input
	@(link_name="ImGuiIO_AddInputCharacterUTF16")            IO_AddInputCharacterUTF16            :: proc(self: ^IO, _c: Wchar16)                                                                              --- // Queue a new character input from a UTF-16 character, it can be a surrogate
	@(link_name="ImGuiIO_AddInputCharactersUTF8")            IO_AddInputCharactersUTF8            :: proc(self: ^IO, str: cstring)                                                                             --- // Queue a new characters input from a UTF-8 string
	@(link_name="ImGuiIO_SetKeyEventNativeData")             IO_SetKeyEventNativeData             :: proc(self: ^IO, key: Key, native_keycode: c.int, native_scancode: c.int, native_legacy_index: c.int = -1) --- // [Optional] Specify index for legacy <1.87 IsKeyXXX() functions with native indices + specify native keycode, scancode.
	@(link_name="ImGuiIO_SetAppAcceptingEvents")             IO_SetAppAcceptingEvents             :: proc(self: ^IO, accepting_events: bool)                                                                   --- // Set master flag for accepting key/mouse/text events (default to true). Useful if you have native dialog boxes that are interrupting your application loop/refresh, and you want to disable events being queued while your app is frozen.
	@(link_name="ImGuiIO_ClearEventsQueue")                  IO_ClearEventsQueue                  :: proc(self: ^IO)                                                                                           --- // Clear all incoming events.
	@(link_name="ImGuiIO_ClearInputKeys")                    IO_ClearInputKeys                    :: proc(self: ^IO)                                                                                           --- // Clear current keyboard/gamepad state + current frame text input buffer. Equivalent to releasing all keys/buttons.
	@(link_name="ImGuiIO_ClearInputMouse")                   IO_ClearInputMouse                   :: proc(self: ^IO)                                                                                           --- // Clear current mouse state.
	@(link_name="ImGuiInputTextCallbackData_DeleteChars")    InputTextCallbackData_DeleteChars    :: proc(self: ^InputTextCallbackData, pos: c.int, bytes_count: c.int)                                        ---
	@(link_name="ImGuiInputTextCallbackData_InsertChars")    InputTextCallbackData_InsertChars    :: proc(self: ^InputTextCallbackData, pos: c.int, text: cstring, text_end: cstring = nil)                    ---
	@(link_name="ImGuiInputTextCallbackData_SelectAll")      InputTextCallbackData_SelectAll      :: proc(self: ^InputTextCallbackData)                                                                        ---
	@(link_name="ImGuiInputTextCallbackData_ClearSelection") InputTextCallbackData_ClearSelection :: proc(self: ^InputTextCallbackData)                                                                        ---
	@(link_name="ImGuiInputTextCallbackData_HasSelection")   InputTextCallbackData_HasSelection   :: proc(self: ^InputTextCallbackData) -> bool                                                                ---
	@(link_name="ImGuiPayload_Clear")                        Payload_Clear                        :: proc(self: ^Payload)                                                                                      ---
	@(link_name="ImGuiPayload_IsDataType")                   Payload_IsDataType                   :: proc(self: ^Payload, type: cstring) -> bool                                                               ---
	@(link_name="ImGuiPayload_IsPreview")                    Payload_IsPreview                    :: proc(self: ^Payload) -> bool                                                                              ---
	@(link_name="ImGuiPayload_IsDelivery")                   Payload_IsDelivery                   :: proc(self: ^Payload) -> bool                                                                              ---
	@(link_name="ImGuiTextFilter_ImGuiTextRange_empty")      TextFilter_ImGuiTextRange_empty      :: proc(self: ^TextFilter_ImGuiTextRange) -> bool                                                            ---
	@(link_name="ImGuiTextFilter_ImGuiTextRange_split")      TextFilter_ImGuiTextRange_split      :: proc(self: ^TextFilter_ImGuiTextRange, separator: c.char, out: ^Vector_TextFilter_ImGuiTextRange)         ---
	@(link_name="ImGuiTextFilter_Draw")                      TextFilter_Draw                      :: proc(self: ^TextFilter, label: cstring = "Filter (inc,-exc)", width: f32 = 0.0) -> bool                   --- // Helper calling InputText+Build
	@(link_name="ImGuiTextFilter_PassFilter")                TextFilter_PassFilter                :: proc(self: ^TextFilter, text: cstring, text_end: cstring = nil) -> bool                                   ---
	@(link_name="ImGuiTextFilter_Build")                     TextFilter_Build                     :: proc(self: ^TextFilter)                                                                                   ---
	@(link_name="ImGuiTextFilter_Clear")                     TextFilter_Clear                     :: proc(self: ^TextFilter)                                                                                   ---
	@(link_name="ImGuiTextFilter_IsActive")                  TextFilter_IsActive                  :: proc(self: ^TextFilter) -> bool                                                                           ---
	@(link_name="ImGuiTextBuffer_begin")                     TextBuffer_begin                     :: proc(self: ^TextBuffer) -> cstring                                                                        ---
	@(link_name="ImGuiTextBuffer_end")                       TextBuffer_end                       :: proc(self: ^TextBuffer) -> cstring                                                                        --- // Buf is zero-terminated, so end() will point on the zero-terminator
	@(link_name="ImGuiTextBuffer_size")                      TextBuffer_size                      :: proc(self: ^TextBuffer) -> c.int                                                                          ---
	@(link_name="ImGuiTextBuffer_empty")                     TextBuffer_empty                     :: proc(self: ^TextBuffer) -> bool                                                                           ---
	@(link_name="ImGuiTextBuffer_clear")                     TextBuffer_clear                     :: proc(self: ^TextBuffer)                                                                                   ---
	@(link_name="ImGuiTextBuffer_reserve")                   TextBuffer_reserve                   :: proc(self: ^TextBuffer, capacity: c.int)                                                                  ---
	@(link_name="ImGuiTextBuffer_c_str")                     TextBuffer_c_str                     :: proc(self: ^TextBuffer) -> cstring                                                                        ---
	@(link_name="ImGuiTextBuffer_append")                    TextBuffer_append                    :: proc(self: ^TextBuffer, str: cstring, str_end: cstring = nil)                                             ---
	@(link_name="ImGuiTextBuffer_appendf")                   TextBuffer_appendf                   :: proc(self: ^TextBuffer, fmt: cstring, #c_vararg args: ..any)                                              ---
	// - Get***() functions find pair, never add/allocate. Pairs are sorted so a query is O(log N)
	// - Set***() functions find pair, insertion on demand if missing.
	// - Sorted insertion is costly, paid once. A typical frame shouldn't need to insert any new pair.
	@(link_name="ImGuiStorage_Clear")      Storage_Clear      :: proc(self: ^Storage)                                             ---
	@(link_name="ImGuiStorage_GetInt")     Storage_GetInt     :: proc(self: ^Storage, key: ID, default_val: c.int = {}) -> c.int  ---
	@(link_name="ImGuiStorage_SetInt")     Storage_SetInt     :: proc(self: ^Storage, key: ID, val: c.int)                        ---
	@(link_name="ImGuiStorage_GetBool")    Storage_GetBool    :: proc(self: ^Storage, key: ID, default_val: bool = false) -> bool ---
	@(link_name="ImGuiStorage_SetBool")    Storage_SetBool    :: proc(self: ^Storage, key: ID, val: bool)                         ---
	@(link_name="ImGuiStorage_GetFloat")   Storage_GetFloat   :: proc(self: ^Storage, key: ID, default_val: f32 = 0.0) -> f32     ---
	@(link_name="ImGuiStorage_SetFloat")   Storage_SetFloat   :: proc(self: ^Storage, key: ID, val: f32)                          ---
	@(link_name="ImGuiStorage_GetVoidPtr") Storage_GetVoidPtr :: proc(self: ^Storage, key: ID) -> rawptr                          --- // default_val is NULL
	@(link_name="ImGuiStorage_SetVoidPtr") Storage_SetVoidPtr :: proc(self: ^Storage, key: ID, val: rawptr)                       ---
	// - Get***Ref() functions finds pair, insert on demand if missing, return pointer. Useful if you intend to do Get+Set.
	// - References are only valid until a new value is added to the storage. Calling a Set***() function or a Get***Ref() function invalidates the pointer.
	// - A typical use case where this is convenient for quick hacking (e.g. add storage during a live Edit&Continue session if you can't modify existing struct)
	//      float* pvar = ImGui::GetFloatRef(key); ImGui::SliderFloat("var", pvar, 0, 100.0f); some_var += *pvar;
	@(link_name="ImGuiStorage_GetIntRef")     Storage_GetIntRef     :: proc(self: ^Storage, key: ID, default_val: c.int = {}) -> ^c.int    ---
	@(link_name="ImGuiStorage_GetBoolRef")    Storage_GetBoolRef    :: proc(self: ^Storage, key: ID, default_val: bool = false) -> ^bool   ---
	@(link_name="ImGuiStorage_GetFloatRef")   Storage_GetFloatRef   :: proc(self: ^Storage, key: ID, default_val: f32 = 0.0) -> ^f32       ---
	@(link_name="ImGuiStorage_GetVoidPtrRef") Storage_GetVoidPtrRef :: proc(self: ^Storage, key: ID, default_val: rawptr = nil) -> ^rawptr ---
	// Advanced: for quicker full rebuild of a storage (instead of an incremental one), you may add all your contents and then sort once.
	@(link_name="ImGuiStorage_BuildSortByKey") Storage_BuildSortByKey :: proc(self: ^Storage) ---
	// Obsolete: use on your own storage if you know only integer are being stored (open/close all tree nodes)
	@(link_name="ImGuiStorage_SetAllInt") Storage_SetAllInt :: proc(self: ^Storage, val: c.int)                                       ---
	@(link_name="ImGuiListClipper_Begin") ListClipper_Begin :: proc(self: ^ListClipper, items_count: c.int, items_height: f32 = -1.0) ---
	@(link_name="ImGuiListClipper_End")   ListClipper_End   :: proc(self: ^ListClipper)                                               --- // Automatically called on the last call of Step() that returns false.
	@(link_name="ImGuiListClipper_Step")  ListClipper_Step  :: proc(self: ^ListClipper) -> bool                                       --- // Call until it returns false. The DisplayStart/DisplayEnd fields will be set and you can process/draw those items.
	// Call IncludeItemByIndex() or IncludeItemsByIndex() *BEFORE* first call to Step() if you need a range of items to not be clipped, regardless of their visibility.
	// (Due to alignment / padding of certain items it is possible that an extra item may be included on either end of the display range).
	@(link_name="ImGuiListClipper_IncludeItemByIndex")  ListClipper_IncludeItemByIndex  :: proc(self: ^ListClipper, item_index: c.int)                  ---
	@(link_name="ImGuiListClipper_IncludeItemsByIndex") ListClipper_IncludeItemsByIndex :: proc(self: ^ListClipper, item_begin: c.int, item_end: c.int) --- // item_end is exclusive e.g. use (42, 42+1) to make item 42 never clipped.
	// Seek cursor toward given item. This is automatically called while stepping.
	// - The only reason to call this is: you can use ImGuiListClipper::Begin(INT_MAX) if you don't know item count ahead of time.
	// - In this case, after all steps are done, you'll want to call SeekCursorForItem(item_count).
	@(link_name="ImGuiListClipper_SeekCursorForItem") ListClipper_SeekCursorForItem :: proc(self: ^ListClipper, item_index: c.int) ---
	// FIXME-OBSOLETE: May need to obsolete/cleanup those helpers.
	@(link_name="ImColor_SetHSV")                                   Color_SetHSV                                :: proc(self: ^Color, h: f32, s: f32, v: f32, a: f32 = 1.0)                    ---
	@(link_name="ImColor_HSV")                                      Color_HSV                                   :: proc(h: f32, s: f32, v: f32, a: f32 = 1.0) -> Color                         ---
	@(link_name="ImGuiSelectionBasicStorage_ApplyRequests")         SelectionBasicStorage_ApplyRequests         :: proc(self: ^SelectionBasicStorage, ms_io: ^MultiSelectIO)                   --- // Apply selection requests coming from BeginMultiSelect() and EndMultiSelect() functions. It uses 'items_count' passed to BeginMultiSelect()
	@(link_name="ImGuiSelectionBasicStorage_Contains")              SelectionBasicStorage_Contains              :: proc(self: ^SelectionBasicStorage, id: ID) -> bool                          --- // Query if an item id is in selection.
	@(link_name="ImGuiSelectionBasicStorage_Clear")                 SelectionBasicStorage_Clear                 :: proc(self: ^SelectionBasicStorage)                                          --- // Clear selection
	@(link_name="ImGuiSelectionBasicStorage_Swap")                  SelectionBasicStorage_Swap                  :: proc(self: ^SelectionBasicStorage, r: ^SelectionBasicStorage)               --- // Swap two selections
	@(link_name="ImGuiSelectionBasicStorage_SetItemSelected")       SelectionBasicStorage_SetItemSelected       :: proc(self: ^SelectionBasicStorage, id: ID, selected: bool)                  --- // Add/remove an item from selection (generally done by ApplyRequests() function)
	@(link_name="ImGuiSelectionBasicStorage_GetNextSelectedItem")   SelectionBasicStorage_GetNextSelectedItem   :: proc(self: ^SelectionBasicStorage, opaque_it: ^rawptr, out_id: ^ID) -> bool --- // Iterate selection with 'void* it = NULL; ImGuiID id; while (selection.GetNextSelectedItem(&it, &id)) { ... }'
	@(link_name="ImGuiSelectionBasicStorage_GetStorageIdFromIndex") SelectionBasicStorage_GetStorageIdFromIndex :: proc(self: ^SelectionBasicStorage, idx: c.int) -> ID                        --- // Convert index to item id based on provided adapter.
	@(link_name="ImGuiSelectionExternalStorage_ApplyRequests")      SelectionExternalStorage_ApplyRequests      :: proc(self: ^SelectionExternalStorage, ms_io: ^MultiSelectIO)                --- // Apply selection requests by using AdapterSetItemSelected() calls
	// Since 1.83: returns ImTextureID associated with this draw call. Warning: DO NOT assume this is always same as 'TextureId' (we will change this function for an upcoming feature)
	@(link_name="ImDrawCmd_GetTexID")                   DrawCmd_GetTexID                   :: proc(self: ^DrawCmd) -> TextureID                                                                               ---
	@(link_name="ImDrawListSplitter_Clear")             DrawListSplitter_Clear             :: proc(self: ^DrawListSplitter)                                                                                   --- // Do not clear Channels[] so our allocations are reused next frame
	@(link_name="ImDrawListSplitter_ClearFreeMemory")   DrawListSplitter_ClearFreeMemory   :: proc(self: ^DrawListSplitter)                                                                                   ---
	@(link_name="ImDrawListSplitter_Split")             DrawListSplitter_Split             :: proc(self: ^DrawListSplitter, draw_list: ^DrawList, count: c.int)                                               ---
	@(link_name="ImDrawListSplitter_Merge")             DrawListSplitter_Merge             :: proc(self: ^DrawListSplitter, draw_list: ^DrawList)                                                             ---
	@(link_name="ImDrawListSplitter_SetCurrentChannel") DrawListSplitter_SetCurrentChannel :: proc(self: ^DrawListSplitter, draw_list: ^DrawList, channel_idx: c.int)                                         ---
	@(link_name="ImDrawList_PushClipRect")              DrawList_PushClipRect              :: proc(self: ^DrawList, clip_rect_min: Vec2, clip_rect_max: Vec2, intersect_with_current_clip_rect: bool = false) --- // Render-level scissoring. This is passed down to your render function but not used for CPU-side coarse clipping. Prefer using higher-level ImGui::PushClipRect() to affect logic (hit-testing and widget culling)
	@(link_name="ImDrawList_PushClipRectFullScreen")    DrawList_PushClipRectFullScreen    :: proc(self: ^DrawList)                                                                                           ---
	@(link_name="ImDrawList_PopClipRect")               DrawList_PopClipRect               :: proc(self: ^DrawList)                                                                                           ---
	@(link_name="ImDrawList_PushTextureID")             DrawList_PushTextureID             :: proc(self: ^DrawList, texture_id: TextureID)                                                                    ---
	@(link_name="ImDrawList_PopTextureID")              DrawList_PopTextureID              :: proc(self: ^DrawList)                                                                                           ---
	@(link_name="ImDrawList_GetClipRectMin")            DrawList_GetClipRectMin            :: proc(self: ^DrawList) -> Vec2                                                                                   ---
	@(link_name="ImDrawList_GetClipRectMax")            DrawList_GetClipRectMax            :: proc(self: ^DrawList) -> Vec2                                                                                   ---
	// Primitives
	// - Filled shapes must always use clockwise winding order. The anti-aliasing fringe depends on it. Counter-clockwise shapes will have "inward" anti-aliasing.
	// - For rectangular primitives, "p_min" and "p_max" represent the upper-left and lower-right corners.
	// - For circle primitives, use "num_segments == 0" to automatically calculate tessellation (preferred).
	//   In older versions (until Dear ImGui 1.77) the AddCircle functions defaulted to num_segments == 12.
	//   In future versions we will use textures to provide cheaper and higher-quality circles.
	//   Use AddNgon() and AddNgonFilled() functions if you need to guarantee a specific number of sides.
	@(link_name="ImDrawList_AddLine")                 DrawList_AddLine                 :: proc(self: ^DrawList, p1: Vec2, p2: Vec2, col: u32, thickness: f32 = 1.0)                                                                                                     ---
	@(link_name="ImDrawList_AddRect")                 DrawList_AddRect                 :: proc(self: ^DrawList, p_min: Vec2, p_max: Vec2, col: u32, rounding: f32 = 0.0, flags: DrawFlags = {}, thickness: f32 = 1.0)                                                   --- // a: upper-left, b: lower-right (== upper-left + size)
	@(link_name="ImDrawList_AddRectFilled")           DrawList_AddRectFilled           :: proc(self: ^DrawList, p_min: Vec2, p_max: Vec2, col: u32, rounding: f32 = 0.0, flags: DrawFlags = {})                                                                         --- // a: upper-left, b: lower-right (== upper-left + size)
	@(link_name="ImDrawList_AddRectFilledMultiColor") DrawList_AddRectFilledMultiColor :: proc(self: ^DrawList, p_min: Vec2, p_max: Vec2, col_upr_left: u32, col_upr_right: u32, col_bot_right: u32, col_bot_left: u32)                                                 ---
	@(link_name="ImDrawList_AddQuad")                 DrawList_AddQuad                 :: proc(self: ^DrawList, p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, col: u32, thickness: f32 = 1.0)                                                                                 ---
	@(link_name="ImDrawList_AddQuadFilled")           DrawList_AddQuadFilled           :: proc(self: ^DrawList, p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, col: u32)                                                                                                       ---
	@(link_name="ImDrawList_AddTriangle")             DrawList_AddTriangle             :: proc(self: ^DrawList, p1: Vec2, p2: Vec2, p3: Vec2, col: u32, thickness: f32 = 1.0)                                                                                           ---
	@(link_name="ImDrawList_AddTriangleFilled")       DrawList_AddTriangleFilled       :: proc(self: ^DrawList, p1: Vec2, p2: Vec2, p3: Vec2, col: u32)                                                                                                                 ---
	@(link_name="ImDrawList_AddCircle")               DrawList_AddCircle               :: proc(self: ^DrawList, center: Vec2, radius: f32, col: u32, num_segments: c.int = {}, thickness: f32 = 1.0)                                                                    ---
	@(link_name="ImDrawList_AddCircleFilled")         DrawList_AddCircleFilled         :: proc(self: ^DrawList, center: Vec2, radius: f32, col: u32, num_segments: c.int = {})                                                                                          ---
	@(link_name="ImDrawList_AddNgon")                 DrawList_AddNgon                 :: proc(self: ^DrawList, center: Vec2, radius: f32, col: u32, num_segments: c.int, thickness: f32 = 1.0)                                                                         ---
	@(link_name="ImDrawList_AddNgonFilled")           DrawList_AddNgonFilled           :: proc(self: ^DrawList, center: Vec2, radius: f32, col: u32, num_segments: c.int)                                                                                               ---
	@(link_name="ImDrawList_AddEllipse")              DrawList_AddEllipse              :: proc(self: ^DrawList, center: Vec2, radius: Vec2, col: u32, rot: f32 = 0.0, num_segments: c.int = {}, thickness: f32 = 1.0)                                                   ---
	@(link_name="ImDrawList_AddEllipseFilled")        DrawList_AddEllipseFilled        :: proc(self: ^DrawList, center: Vec2, radius: Vec2, col: u32, rot: f32 = 0.0, num_segments: c.int = {})                                                                         ---
	@(link_name="ImDrawList_AddText")                 DrawList_AddText                 :: proc(self: ^DrawList, pos: Vec2, col: u32, text_begin: cstring, text_end: cstring = nil)                                                                                      ---
	@(link_name="ImDrawList_AddTextImFontPtr")        DrawList_AddTextImFontPtr        :: proc(self: ^DrawList, font: ^Font, font_size: f32, pos: Vec2, col: u32, text_begin: cstring, text_end: cstring = nil, wrap_width: f32 = 0.0, cpu_fine_clip_rect: ^Vec4 = nil) ---
	@(link_name="ImDrawList_AddBezierCubic")          DrawList_AddBezierCubic          :: proc(self: ^DrawList, p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, col: u32, thickness: f32, num_segments: c.int = {})                                                             --- // Cubic Bezier (4 control points)
	@(link_name="ImDrawList_AddBezierQuadratic")      DrawList_AddBezierQuadratic      :: proc(self: ^DrawList, p1: Vec2, p2: Vec2, p3: Vec2, col: u32, thickness: f32, num_segments: c.int = {})                                                                       --- // Quadratic Bezier (3 control points)
	// General polygon
	// - Only simple polygons are supported by filling functions (no self-intersections, no holes).
	// - Concave polygon fill is more expensive than convex one: it has O(N^2) complexity. Provided as a convenience fo user but not used by main library.
	@(link_name="ImDrawList_AddPolyline")          DrawList_AddPolyline          :: proc(self: ^DrawList, points: ^Vec2, num_points: c.int, col: u32, flags: DrawFlags, thickness: f32) ---
	@(link_name="ImDrawList_AddConvexPolyFilled")  DrawList_AddConvexPolyFilled  :: proc(self: ^DrawList, points: ^Vec2, num_points: c.int, col: u32)                                   ---
	@(link_name="ImDrawList_AddConcavePolyFilled") DrawList_AddConcavePolyFilled :: proc(self: ^DrawList, points: ^Vec2, num_points: c.int, col: u32)                                   ---
	// Image primitives
	// - Read FAQ to understand what ImTextureID is.
	// - "p_min" and "p_max" represent the upper-left and lower-right corners of the rectangle.
	// - "uv_min" and "uv_max" represent the normalized texture coordinates to use for those corners. Using (0,0)->(1,1) texture coordinates will generally display the entire texture.
	@(link_name="ImDrawList_AddImage")        DrawList_AddImage        :: proc(self: ^DrawList, user_texture_id: TextureID, p_min: Vec2, p_max: Vec2, uv_min: Vec2 = {0, 0}, uv_max: Vec2 = {1, 1}, col: u32 = 0xff_ff_ff_ff)                                                 ---
	@(link_name="ImDrawList_AddImageQuad")    DrawList_AddImageQuad    :: proc(self: ^DrawList, user_texture_id: TextureID, p1: Vec2, p2: Vec2, p3: Vec2, p4: Vec2, uv1: Vec2 = {0, 0}, uv2: Vec2 = {1, 0}, uv3: Vec2 = {1, 1}, uv4: Vec2 = {0, 1}, col: u32 = 0xff_ff_ff_ff) ---
	@(link_name="ImDrawList_AddImageRounded") DrawList_AddImageRounded :: proc(self: ^DrawList, user_texture_id: TextureID, p_min: Vec2, p_max: Vec2, uv_min: Vec2, uv_max: Vec2, col: u32, rounding: f32, flags: DrawFlags = {})                                             ---
	// Stateful path API, add points then finish with PathFillConvex() or PathStroke()
	// - Important: filled shapes must always use clockwise winding order! The anti-aliasing fringe depends on it. Counter-clockwise shapes will have "inward" anti-aliasing.
	//   so e.g. 'PathArcTo(center, radius, PI * -0.5f, PI)' is ok, whereas 'PathArcTo(center, radius, PI, PI * -0.5f)' won't have correct anti-aliasing when followed by PathFillConvex().
	@(link_name="ImDrawList_PathClear")                  DrawList_PathClear                  :: proc(self: ^DrawList)                                                                                         ---
	@(link_name="ImDrawList_PathLineTo")                 DrawList_PathLineTo                 :: proc(self: ^DrawList, pos: Vec2)                                                                              ---
	@(link_name="ImDrawList_PathLineToMergeDuplicate")   DrawList_PathLineToMergeDuplicate   :: proc(self: ^DrawList, pos: Vec2)                                                                              ---
	@(link_name="ImDrawList_PathFillConvex")             DrawList_PathFillConvex             :: proc(self: ^DrawList, col: u32)                                                                               ---
	@(link_name="ImDrawList_PathFillConcave")            DrawList_PathFillConcave            :: proc(self: ^DrawList, col: u32)                                                                               ---
	@(link_name="ImDrawList_PathStroke")                 DrawList_PathStroke                 :: proc(self: ^DrawList, col: u32, flags: DrawFlags = {}, thickness: f32 = 1.0)                                  ---
	@(link_name="ImDrawList_PathArcTo")                  DrawList_PathArcTo                  :: proc(self: ^DrawList, center: Vec2, radius: f32, a_min: f32, a_max: f32, num_segments: c.int = {})            ---
	@(link_name="ImDrawList_PathArcToFast")              DrawList_PathArcToFast              :: proc(self: ^DrawList, center: Vec2, radius: f32, a_min_of_12: c.int, a_max_of_12: c.int)                      --- // Use precomputed angles for a 12 steps circle
	@(link_name="ImDrawList_PathEllipticalArcTo")        DrawList_PathEllipticalArcTo        :: proc(self: ^DrawList, center: Vec2, radius: Vec2, rot: f32, a_min: f32, a_max: f32, num_segments: c.int = {}) --- // Ellipse
	@(link_name="ImDrawList_PathBezierCubicCurveTo")     DrawList_PathBezierCubicCurveTo     :: proc(self: ^DrawList, p2: Vec2, p3: Vec2, p4: Vec2, num_segments: c.int = {})                                 --- // Cubic Bezier (4 control points)
	@(link_name="ImDrawList_PathBezierQuadraticCurveTo") DrawList_PathBezierQuadraticCurveTo :: proc(self: ^DrawList, p2: Vec2, p3: Vec2, num_segments: c.int = {})                                           --- // Quadratic Bezier (3 control points)
	@(link_name="ImDrawList_PathRect")                   DrawList_PathRect                   :: proc(self: ^DrawList, rect_min: Vec2, rect_max: Vec2, rounding: f32 = 0.0, flags: DrawFlags = {})             ---
	// Advanced: Draw Callbacks
	// - May be used to alter render state (change sampler, blending, current shader). May be used to emit custom rendering commands (difficult to do correctly, but possible).
	// - Use special ImDrawCallback_ResetRenderState callback to instruct backend to reset its render state to the default.
	// - Your rendering loop must check for 'UserCallback' in ImDrawCmd and call the function instead of rendering triangles. All standard backends are honoring this.
	// - For some backends, the callback may access selected render-states exposed by the backend in a ImGui_ImplXXXX_RenderState structure pointed to by platform_io.Renderer_RenderState.
	// - IMPORTANT: please be mindful of the different level of indirection between using size==0 (copying argument) and using size>0 (copying pointed data into a buffer).
	//   - If userdata_size == 0: we copy/store the 'userdata' argument as-is. It will be available unmodified in ImDrawCmd::UserCallbackData during render.
	//   - If userdata_size > 0,  we copy/store 'userdata_size' bytes pointed to by 'userdata'. We store them in a buffer stored inside the drawlist. ImDrawCmd::UserCallbackData will point inside that buffer so you have to retrieve data from there. Your callback may need to use ImDrawCmd::UserCallbackDataSize if you expect dynamically-sized data.
	//   - Support for userdata_size > 0 was added in v1.91.4, October 2024. So earlier code always only allowed to copy/store a simple void*.
	@(link_name="ImDrawList_AddCallback") DrawList_AddCallback :: proc(self: ^DrawList, callback: DrawCallback, userdata: rawptr, userdata_size: c.size_t = {}) ---
	// Advanced: Miscellaneous
	@(link_name="ImDrawList_AddDrawCmd")  DrawList_AddDrawCmd  :: proc(self: ^DrawList)              --- // This is useful if you need to forcefully create a new draw call (to allow for dependent rendering / blending). Otherwise primitives are merged into the same draw-call as much as possible
	@(link_name="ImDrawList_CloneOutput") DrawList_CloneOutput :: proc(self: ^DrawList) -> ^DrawList --- // Create a clone of the CmdBuffer/IdxBuffer/VtxBuffer.
	// Advanced: Channels
	// - Use to split render into layers. By switching channels to can render out-of-order (e.g. submit FG primitives before BG primitives)
	// - Use to minimize draw calls (e.g. if going back-and-forth between multiple clipping rectangles, prefer to append into separate channels then merge at the end)
	// - This API shouldn't have been in ImDrawList in the first place!
	//   Prefer using your own persistent instance of ImDrawListSplitter as you can stack them.
	//   Using the ImDrawList::ChannelsXXXX you cannot stack a split over another.
	@(link_name="ImDrawList_ChannelsSplit")      DrawList_ChannelsSplit      :: proc(self: ^DrawList, count: c.int) ---
	@(link_name="ImDrawList_ChannelsMerge")      DrawList_ChannelsMerge      :: proc(self: ^DrawList)               ---
	@(link_name="ImDrawList_ChannelsSetCurrent") DrawList_ChannelsSetCurrent :: proc(self: ^DrawList, n: c.int)     ---
	// Advanced: Primitives allocations
	// - We render triangles (three vertices)
	// - All primitives needs to be reserved via PrimReserve() beforehand.
	@(link_name="ImDrawList_PrimReserve")   DrawList_PrimReserve   :: proc(self: ^DrawList, idx_count: c.int, vtx_count: c.int)                                                            ---
	@(link_name="ImDrawList_PrimUnreserve") DrawList_PrimUnreserve :: proc(self: ^DrawList, idx_count: c.int, vtx_count: c.int)                                                            ---
	@(link_name="ImDrawList_PrimRect")      DrawList_PrimRect      :: proc(self: ^DrawList, a: Vec2, b: Vec2, col: u32)                                                                    --- // Axis aligned rectangle (composed of two triangles)
	@(link_name="ImDrawList_PrimRectUV")    DrawList_PrimRectUV    :: proc(self: ^DrawList, a: Vec2, b: Vec2, uv_a: Vec2, uv_b: Vec2, col: u32)                                            ---
	@(link_name="ImDrawList_PrimQuadUV")    DrawList_PrimQuadUV    :: proc(self: ^DrawList, a: Vec2, b: Vec2, _c: Vec2, d: Vec2, uv_a: Vec2, uv_b: Vec2, uv_c: Vec2, uv_d: Vec2, col: u32) ---
	@(link_name="ImDrawList_PrimWriteVtx")  DrawList_PrimWriteVtx  :: proc(self: ^DrawList, pos: Vec2, uv: Vec2, col: u32)                                                                 ---
	@(link_name="ImDrawList_PrimWriteIdx")  DrawList_PrimWriteIdx  :: proc(self: ^DrawList, idx: DrawIdx)                                                                                  ---
	@(link_name="ImDrawList_PrimVtx")       DrawList_PrimVtx       :: proc(self: ^DrawList, pos: Vec2, uv: Vec2, col: u32)                                                                 --- // Write vertex with unique index
	// [Internal helpers]
	@(link_name="ImDrawList__ResetForNewFrame")                     DrawList__ResetForNewFrame                     :: proc(self: ^DrawList)                                                                                                                                                      ---
	@(link_name="ImDrawList__ClearFreeMemory")                      DrawList__ClearFreeMemory                      :: proc(self: ^DrawList)                                                                                                                                                      ---
	@(link_name="ImDrawList__PopUnusedDrawCmd")                     DrawList__PopUnusedDrawCmd                     :: proc(self: ^DrawList)                                                                                                                                                      ---
	@(link_name="ImDrawList__TryMergeDrawCmds")                     DrawList__TryMergeDrawCmds                     :: proc(self: ^DrawList)                                                                                                                                                      ---
	@(link_name="ImDrawList__OnChangedClipRect")                    DrawList__OnChangedClipRect                    :: proc(self: ^DrawList)                                                                                                                                                      ---
	@(link_name="ImDrawList__OnChangedTextureID")                   DrawList__OnChangedTextureID                   :: proc(self: ^DrawList)                                                                                                                                                      ---
	@(link_name="ImDrawList__OnChangedVtxOffset")                   DrawList__OnChangedVtxOffset                   :: proc(self: ^DrawList)                                                                                                                                                      ---
	@(link_name="ImDrawList__SetTextureID")                         DrawList__SetTextureID                         :: proc(self: ^DrawList, texture_id: TextureID)                                                                                                                               ---
	@(link_name="ImDrawList__CalcCircleAutoSegmentCount")           DrawList__CalcCircleAutoSegmentCount           :: proc(self: ^DrawList, radius: f32) -> c.int                                                                                                                                ---
	@(link_name="ImDrawList__PathArcToFastEx")                      DrawList__PathArcToFastEx                      :: proc(self: ^DrawList, center: Vec2, radius: f32, a_min_sample: c.int, a_max_sample: c.int, a_step: c.int)                                                                  ---
	@(link_name="ImDrawList__PathArcToN")                           DrawList__PathArcToN                           :: proc(self: ^DrawList, center: Vec2, radius: f32, a_min: f32, a_max: f32, num_segments: c.int)                                                                              ---
	@(link_name="ImDrawData_Clear")                                 DrawData_Clear                                 :: proc(self: ^DrawData)                                                                                                                                                      ---
	@(link_name="ImDrawData_AddDrawList")                           DrawData_AddDrawList                           :: proc(self: ^DrawData, draw_list: ^DrawList)                                                                                                                                --- // Helper to add an external draw list into an existing ImDrawData.
	@(link_name="ImDrawData_DeIndexAllBuffers")                     DrawData_DeIndexAllBuffers                     :: proc(self: ^DrawData)                                                                                                                                                      --- // Helper to convert all buffers from indexed to non-indexed, in case you cannot render indexed. Note: this is slow and most likely a waste of resources. Always prefer indexed rendering!
	@(link_name="ImDrawData_ScaleClipRects")                        DrawData_ScaleClipRects                        :: proc(self: ^DrawData, fb_scale: Vec2)                                                                                                                                      --- // Helper to scale the ClipRect field of each ImDrawCmd. Use if your final output buffer is at a different scale than Dear ImGui expects, or if there is a difference between your window resolution and framebuffer resolution.
	@(link_name="ImFontGlyphRangesBuilder_Clear")                   FontGlyphRangesBuilder_Clear                   :: proc(self: ^FontGlyphRangesBuilder)                                                                                                                                        ---
	@(link_name="ImFontGlyphRangesBuilder_GetBit")                  FontGlyphRangesBuilder_GetBit                  :: proc(self: ^FontGlyphRangesBuilder, n: c.size_t) -> bool                                                                                                                   --- // Get bit n in the array
	@(link_name="ImFontGlyphRangesBuilder_SetBit")                  FontGlyphRangesBuilder_SetBit                  :: proc(self: ^FontGlyphRangesBuilder, n: c.size_t)                                                                                                                           --- // Set bit n in the array
	@(link_name="ImFontGlyphRangesBuilder_AddChar")                 FontGlyphRangesBuilder_AddChar                 :: proc(self: ^FontGlyphRangesBuilder, _c: Wchar)                                                                                                                             --- // Add character
	@(link_name="ImFontGlyphRangesBuilder_AddText")                 FontGlyphRangesBuilder_AddText                 :: proc(self: ^FontGlyphRangesBuilder, text: cstring, text_end: cstring = nil)                                                                                                --- // Add string (each character of the UTF-8 string are added)
	@(link_name="ImFontGlyphRangesBuilder_AddRanges")               FontGlyphRangesBuilder_AddRanges               :: proc(self: ^FontGlyphRangesBuilder, ranges: ^Wchar)                                                                                                                        --- // Add ranges, e.g. builder.AddRanges(ImFontAtlas::GetGlyphRangesDefault()) to force add all of ASCII/Latin+Ext
	@(link_name="ImFontGlyphRangesBuilder_BuildRanges")             FontGlyphRangesBuilder_BuildRanges             :: proc(self: ^FontGlyphRangesBuilder, out_ranges: ^Vector_Wchar)                                                                                                             --- // Output new ranges (ImVector_Construct()/ImVector_Destruct() can be used to safely construct out_ranges)
	@(link_name="ImFontAtlasCustomRect_IsPacked")                   FontAtlasCustomRect_IsPacked                   :: proc(self: ^FontAtlasCustomRect) -> bool                                                                                                                                   ---
	@(link_name="ImFontAtlas_AddFont")                              FontAtlas_AddFont                              :: proc(self: ^FontAtlas, font_cfg: ^FontConfig) -> ^Font                                                                                                                     ---
	@(link_name="ImFontAtlas_AddFontDefault")                       FontAtlas_AddFontDefault                       :: proc(self: ^FontAtlas, font_cfg: ^FontConfig = nil) -> ^Font                                                                                                               ---
	@(link_name="ImFontAtlas_AddFontFromFileTTF")                   FontAtlas_AddFontFromFileTTF                   :: proc(self: ^FontAtlas, filename: cstring, size_pixels: f32, font_cfg: ^FontConfig = nil, glyph_ranges: ^Wchar = nil) -> ^Font                                              ---
	@(link_name="ImFontAtlas_AddFontFromMemoryTTF")                 FontAtlas_AddFontFromMemoryTTF                 :: proc(self: ^FontAtlas, font_data: rawptr, font_data_size: c.int, size_pixels: f32, font_cfg: ^FontConfig = nil, glyph_ranges: ^Wchar = nil) -> ^Font                       --- // Note: Transfer ownership of 'ttf_data' to ImFontAtlas! Will be deleted after destruction of the atlas. Set font_cfg->FontDataOwnedByAtlas=false to keep ownership of your data and it won't be freed.
	@(link_name="ImFontAtlas_AddFontFromMemoryCompressedTTF")       FontAtlas_AddFontFromMemoryCompressedTTF       :: proc(self: ^FontAtlas, compressed_font_data: rawptr, compressed_font_data_size: c.int, size_pixels: f32, font_cfg: ^FontConfig = nil, glyph_ranges: ^Wchar = nil) -> ^Font --- // 'compressed_font_data' still owned by caller. Compress with binary_to_compressed_c.cpp.
	@(link_name="ImFontAtlas_AddFontFromMemoryCompressedBase85TTF") FontAtlas_AddFontFromMemoryCompressedBase85TTF :: proc(self: ^FontAtlas, compressed_font_data_base85: cstring, size_pixels: f32, font_cfg: ^FontConfig = nil, glyph_ranges: ^Wchar = nil) -> ^Font                           --- // 'compressed_font_data_base85' still owned by caller. Compress with binary_to_compressed_c.cpp with -base85 parameter.
	@(link_name="ImFontAtlas_ClearInputData")                       FontAtlas_ClearInputData                       :: proc(self: ^FontAtlas)                                                                                                                                                     --- // Clear input data (all ImFontConfig structures including sizes, TTF data, glyph ranges, etc.) = all the data used to build the texture and fonts.
	@(link_name="ImFontAtlas_ClearTexData")                         FontAtlas_ClearTexData                         :: proc(self: ^FontAtlas)                                                                                                                                                     --- // Clear output texture data (CPU side). Saves RAM once the texture has been copied to graphics memory.
	@(link_name="ImFontAtlas_ClearFonts")                           FontAtlas_ClearFonts                           :: proc(self: ^FontAtlas)                                                                                                                                                     --- // Clear output font data (glyphs storage, UV coordinates).
	@(link_name="ImFontAtlas_Clear")                                FontAtlas_Clear                                :: proc(self: ^FontAtlas)                                                                                                                                                     --- // Clear all input and output.
	// Build atlas, retrieve pixel data.
	// User is in charge of copying the pixels into graphics memory (e.g. create a texture with your engine). Then store your texture handle with SetTexID().
	// The pitch is always = Width * BytesPerPixels (1 or 4)
	// Building in RGBA32 format is provided for convenience and compatibility, but note that unless you manually manipulate or copy color data into
	// the texture (e.g. when using the AddCustomRect*** api), then the RGB pixels emitted will always be white (~75% of memory/bandwidth waste.
	@(link_name="ImFontAtlas_Build")              FontAtlas_Build              :: proc(self: ^FontAtlas) -> bool                                                                                          --- // Build pixels data. This is called automatically for you by the GetTexData*** functions.
	@(link_name="ImFontAtlas_GetTexDataAsAlpha8") FontAtlas_GetTexDataAsAlpha8 :: proc(self: ^FontAtlas, out_pixels: ^^c.uchar, out_width: ^c.int, out_height: ^c.int, out_bytes_per_pixel: ^c.int = nil) --- // 1 byte per-pixel
	@(link_name="ImFontAtlas_GetTexDataAsRGBA32") FontAtlas_GetTexDataAsRGBA32 :: proc(self: ^FontAtlas, out_pixels: ^^c.uchar, out_width: ^c.int, out_height: ^c.int, out_bytes_per_pixel: ^c.int = nil) --- // 4 bytes-per-pixel
	@(link_name="ImFontAtlas_IsBuilt")            FontAtlas_IsBuilt            :: proc(self: ^FontAtlas) -> bool                                                                                          --- // Bit ambiguous: used to detect when user didn't build texture but effectively we should check TexID != 0 except that would be backend dependent...
	@(link_name="ImFontAtlas_SetTexID")           FontAtlas_SetTexID           :: proc(self: ^FontAtlas, id: TextureID)                                                                                   ---
	// Helpers to retrieve list of common Unicode ranges (2 value per range, values are inclusive, zero-terminated list)
	// NB: Make sure that your string are UTF-8 and NOT in your local code page.
	// Read https://github.com/ocornut/imgui/blob/master/docs/FONTS.md/#about-utf-8-encoding for details.
	// NB: Consider using ImFontGlyphRangesBuilder to build glyph ranges from textual data.
	@(link_name="ImFontAtlas_GetGlyphRangesDefault")                 FontAtlas_GetGlyphRangesDefault                 :: proc(self: ^FontAtlas) -> ^Wchar --- // Basic Latin, Extended Latin
	@(link_name="ImFontAtlas_GetGlyphRangesGreek")                   FontAtlas_GetGlyphRangesGreek                   :: proc(self: ^FontAtlas) -> ^Wchar --- // Default + Greek and Coptic
	@(link_name="ImFontAtlas_GetGlyphRangesKorean")                  FontAtlas_GetGlyphRangesKorean                  :: proc(self: ^FontAtlas) -> ^Wchar --- // Default + Korean characters
	@(link_name="ImFontAtlas_GetGlyphRangesJapanese")                FontAtlas_GetGlyphRangesJapanese                :: proc(self: ^FontAtlas) -> ^Wchar --- // Default + Hiragana, Katakana, Half-Width, Selection of 2999 Ideographs
	@(link_name="ImFontAtlas_GetGlyphRangesChineseFull")             FontAtlas_GetGlyphRangesChineseFull             :: proc(self: ^FontAtlas) -> ^Wchar --- // Default + Half-Width + Japanese Hiragana/Katakana + full set of about 21000 CJK Unified Ideographs
	@(link_name="ImFontAtlas_GetGlyphRangesChineseSimplifiedCommon") FontAtlas_GetGlyphRangesChineseSimplifiedCommon :: proc(self: ^FontAtlas) -> ^Wchar --- // Default + Half-Width + Japanese Hiragana/Katakana + set of 2500 CJK Unified Ideographs for common simplified Chinese
	@(link_name="ImFontAtlas_GetGlyphRangesCyrillic")                FontAtlas_GetGlyphRangesCyrillic                :: proc(self: ^FontAtlas) -> ^Wchar --- // Default + about 400 Cyrillic characters
	@(link_name="ImFontAtlas_GetGlyphRangesThai")                    FontAtlas_GetGlyphRangesThai                    :: proc(self: ^FontAtlas) -> ^Wchar --- // Default + Thai characters
	@(link_name="ImFontAtlas_GetGlyphRangesVietnamese")              FontAtlas_GetGlyphRangesVietnamese              :: proc(self: ^FontAtlas) -> ^Wchar --- // Default + Vietnamese characters
	// You can request arbitrary rectangles to be packed into the atlas, for your own purposes.
	// - After calling Build(), you can query the rectangle position and render your pixels.
	// - If you render colored output, set 'atlas->TexPixelsUseColors = true' as this may help some backends decide of preferred texture format.
	// - You can also request your rectangles to be mapped as font glyph (given a font + Unicode point),
	//   so you can render e.g. custom colorful icons and use them as regular glyphs.
	// - Read docs/FONTS.md for more details about using colorful icons.
	// - Note: this API may be redesigned later in order to support multi-monitor varying DPI settings.
	@(link_name="ImFontAtlas_AddCustomRectRegular")   FontAtlas_AddCustomRectRegular   :: proc(self: ^FontAtlas, width: c.int, height: c.int) -> c.int                                                                ---
	@(link_name="ImFontAtlas_AddCustomRectFontGlyph") FontAtlas_AddCustomRectFontGlyph :: proc(self: ^FontAtlas, font: ^Font, id: Wchar, width: c.int, height: c.int, advance_x: f32, offset: Vec2 = {0, 0}) -> c.int ---
	@(link_name="ImFontAtlas_GetCustomRectByIndex")   FontAtlas_GetCustomRectByIndex   :: proc(self: ^FontAtlas, index: c.int) -> ^FontAtlasCustomRect                                                                ---
	// [Internal]
	@(link_name="ImFontAtlas_CalcCustomRectUV")      FontAtlas_CalcCustomRectUV      :: proc(self: ^FontAtlas, rect: ^FontAtlasCustomRect, out_uv_min: ^Vec2, out_uv_max: ^Vec2)                                                ---
	@(link_name="ImFontAtlas_GetMouseCursorTexData") FontAtlas_GetMouseCursorTexData :: proc(self: ^FontAtlas, cursor: MouseCursor, out_offset: ^Vec2, out_size: ^Vec2, out_uv_border: ^[2]Vec2, out_uv_fill: ^[2]Vec2) -> bool ---
	@(link_name="ImFont_FindGlyph")                  Font_FindGlyph                  :: proc(self: ^Font, _c: Wchar) -> ^FontGlyph                                                                                              ---
	@(link_name="ImFont_FindGlyphNoFallback")        Font_FindGlyphNoFallback        :: proc(self: ^Font, _c: Wchar) -> ^FontGlyph                                                                                              ---
	@(link_name="ImFont_GetCharAdvance")             Font_GetCharAdvance             :: proc(self: ^Font, _c: Wchar) -> f32                                                                                                     ---
	@(link_name="ImFont_IsLoaded")                   Font_IsLoaded                   :: proc(self: ^Font) -> bool                                                                                                               ---
	@(link_name="ImFont_GetDebugName")               Font_GetDebugName               :: proc(self: ^Font) -> cstring                                                                                                            ---
	// 'max_width' stops rendering after a certain width (could be turned into a 2d size). FLT_MAX to disable.
	// 'wrap_width' enable automatic word-wrapping across multiple lines to fit into given width. 0.0f to disable.
	@(link_name="ImFont_CalcTextSizeA")         Font_CalcTextSizeA         :: proc(self: ^Font, size: f32, max_width: f32, wrap_width: f32, text_begin: cstring, text_end: cstring = nil, remaining: ^cstring = nil) -> Vec2                                       --- // utf8
	@(link_name="ImFont_CalcWordWrapPositionA") Font_CalcWordWrapPositionA :: proc(self: ^Font, scale: f32, text: cstring, text_end: cstring, wrap_width: f32) -> cstring                                                                                          ---
	@(link_name="ImFont_RenderChar")            Font_RenderChar            :: proc(self: ^Font, draw_list: ^DrawList, size: f32, pos: Vec2, col: u32, _c: Wchar)                                                                                                   ---
	@(link_name="ImFont_RenderText")            Font_RenderText            :: proc(self: ^Font, draw_list: ^DrawList, size: f32, pos: Vec2, col: u32, clip_rect: Vec4, text_begin: cstring, text_end: cstring, wrap_width: f32 = 0.0, cpu_fine_clip: bool = false) ---
	// [Internal] Don't use!
	@(link_name="ImFont_BuildLookupTable")   Font_BuildLookupTable   :: proc(self: ^Font)                                                                                                                          ---
	@(link_name="ImFont_ClearOutputData")    Font_ClearOutputData    :: proc(self: ^Font)                                                                                                                          ---
	@(link_name="ImFont_GrowIndex")          Font_GrowIndex          :: proc(self: ^Font, new_size: c.int)                                                                                                         ---
	@(link_name="ImFont_AddGlyph")           Font_AddGlyph           :: proc(self: ^Font, src_cfg: ^FontConfig, _c: Wchar, x0: f32, y0: f32, x1: f32, y1: f32, u0: f32, v0: f32, u1: f32, v1: f32, advance_x: f32) ---
	@(link_name="ImFont_AddRemapChar")       Font_AddRemapChar       :: proc(self: ^Font, dst: Wchar, src: Wchar, overwrite_dst: bool = true)                                                                      --- // Makes 'dst' character/glyph points to 'src' character/glyph. Currently needs to be called AFTER fonts have been built.
	@(link_name="ImFont_SetGlyphVisible")    Font_SetGlyphVisible    :: proc(self: ^Font, _c: Wchar, visible: bool)                                                                                                ---
	@(link_name="ImFont_IsGlyphRangeUnused") Font_IsGlyphRangeUnused :: proc(self: ^Font, c_begin: c.uint, c_last: c.uint) -> bool                                                                                 ---
	// Helpers
	@(link_name="ImGuiViewport_GetCenter")     Viewport_GetCenter     :: proc(self: ^Viewport) -> Vec2 ---
	@(link_name="ImGuiViewport_GetWorkCenter") Viewport_GetWorkCenter :: proc(self: ^Viewport) -> Vec2 ---
}

////////////////////////////////////////////////////////////
// TYPEDEFS
////////////////////////////////////////////////////////////

// Scalar data types
ID        :: c.uint   // A unique ID used by widgets (typically the result of hashing a stack of string)
KeyChord  :: c.int    // -> ImGuiKey | ImGuiMod_XXX    // Flags: for IsKeyChordPressed(), Shortcut() etc. an ImGuiKey optionally OR-ed with one or more ImGuiMod_XXX values.
TextureID :: u64      // Default: store a pointer or an integer fitting in a pointer (most renderer backends are ok with that)
DrawIdx   :: c.ushort // Default: 16-bit (for maximum compatibility with renderer backends)
// Character types
// (we generally use UTF-8 encoded string in the API. This is storage specifically for a decoded character used for keyboard input and display)
Wchar32 :: rune     // A single decoded U32 character/code point. We encode them as multi bytes UTF-8 when used in strings.
Wchar16 :: c.ushort // A single decoded U16 character/code point. We encode them as multi bytes UTF-8 when used in strings.
Wchar   :: Wchar16
// Multi-Selection item index or identifier when using BeginMultiSelect()
// - Used by SetNextItemSelectionUserData() + and inside ImGuiMultiSelectIO structure.
// - Most users are likely to use this store an item INDEX but this may be used to store a POINTER/ID as well. Read comments near ImGuiMultiSelectIO for details.
SelectionUserData :: i64
// Callback and functions types
InputTextCallback :: proc "c" (data: ^InputTextCallbackData) -> c.int     // Callback function for ImGui::InputText()
SizeCallback      :: proc "c" (data: ^SizeCallbackData)                   // Callback function for ImGui::SetNextWindowSizeConstraints()
MemAllocFunc      :: proc "c" (sz: c.size_t, user_data: rawptr) -> rawptr // Function signature for ImGui::SetAllocatorFunctions()
MemFreeFunc       :: proc "c" (ptr: rawptr, user_data: rawptr)            // Function signature for ImGui::SetAllocatorFunctions()
DrawCallback      :: proc "c" (parent_list: ^DrawList, cmd: ^DrawCmd)
