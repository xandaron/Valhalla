package tinyfiledialogs

import "base:builtin"
import "core:c"

when ODIN_OS == .Darwin {
	foreign import lib "./tinyfiledialogs_macos.a"
} else when ODIN_OS == .Linux {
	// TODO: this is completely untested.
	foreign import lib "./tinyfiledialogs_linux.a"
} else when ODIN_OS == .Windows {
	foreign import lib {"./tinyfiledialogs_windows.lib", "system:User32.lib", "system:Shell32.lib", "system:Comdlg32.lib", "system:Ole32.lib"}
}


@(default_calling_convention = "c")
@(link_prefix = "tinyfd_")
foreign lib {
	// contains tinyfd current version number
	version: [8]c.char
	// info about requirements
	needs: []c.char
	// 0 (default) or 1 : on unix, prints the command line calls
	verbose: c.int
	// 1 (default) or 0 : on unix, hide errors and warnings from called dialogs
	silent: c.int
	// Curses dialogs are difficult to use and counter-intuitive.
	// On windows they are only ascii and still uses the unix backslash !
	// 0 (default) or 1
	allowCursesDialogs: c.int
	// for unix & windows: 0 (graphic mode) or 1 (console mode).
	// 0: try to use a graphic solution, if it fails then it uses console mode.
	// 1: forces all dialogs into console mode even when an X server is present.
	// if enabled, it can use the package Dialog or dialog.exe.
	// on windows it only make sense for console applications
	// 0 (default) or 1
	forceConsole: c.int
	// some systems don't set the environment variable DISPLAY even when a graphic display is present.
	// set this to 1 to tell tinyfiledialogs to assume the existence of a graphic display
	assumeGraphicDisplay: c.int
	// if you pass "tinyfd_query" as aTitle,
	// the functions will not display the dialogs
	// but will return 0 for console mode, 1 for graphic mode.
	// tinyfd_response is then filled with the retain solution.
	// possible values for tinyfd_response are (all lowercase)
	// for graphic mode:
	//   windows_wchar windows applescript kdialog zenity zenity3 yad matedialog
	//   shellementary qarma python2-tkinter python3-tkinter python-dbus
	//   perl-dbus gxmessage gmessage xmessage xdialog gdialog dunst
	// for console mode:
	//   dialog whiptail basicinput no_solution
	response: [1024]c.char

	beep :: proc() ---
	notifyPopup :: proc(aTitle: cstring, aMessage: cstring, aIconType: cstring) -> c.int ---
	messageBox :: proc(aTitle: cstring, aMessage: cstring, aDialogType: cstring, aIconType: cstring, aDefaultButton: c.int) -> c.int ---
	inputBox :: proc(aTitle: cstring, aMessage: cstring, aDefaultInput: cstring) -> cstring ---
	saveFileDialog :: proc(aTitle: cstring, aDefaultPathAndOrFile: cstring, aNumOfFilterPatterns: c.int, aFilterPatterns: [^]cstring, aSingleFilterDescription: cstring) -> cstring ---
	openFileDialog :: proc(aTitle: cstring, aDefaultPathAndOrFile: cstring, aNumOfFilterPatterns: c.int, aFilterPatterns: [^]cstring, aSingleFilterDescription: cstring, aAllowMultipleSelects: c.int) -> cstring ---
	selectFolderDialog :: proc(aTitle: cstring, aDefaultPath: cstring) -> cstring ---
	colorChooser :: proc(aTitle: cstring, aDefaultHexRGB: cstring, aDefaultRGB: [^]c.uchar, aoResultRGB: [^]c.uchar) -> cstring ---
}
