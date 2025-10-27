package tinyfiledialogs

import "base:builtin"
import "core:c"
import win32 "core:sys/windows"

foreign import lib {"./tinyfiledialogs_windows.lib", "system:User32.lib", "system:Shell32.lib", "system:Comdlg32.lib", "system:Ole32.lib"}

@(default_calling_convention = "c")
@(link_prefix = "tinyfd_")
foreign lib {
	winUtf8: c.int

	utf8toMbcs :: proc(aUtf8string: cstring) -> cstring ---
	utf16toMbcs :: proc(aUtf16string: [^]win32.wchar_t) -> cstring ---
	mbcsTo16 :: proc(aMbcsString: cstring) -> [^]win32.wchar_t ---
	mbcsTo8 :: proc(aMbcsString: cstring) -> cstring ---
	utf8to16 :: proc(aUtf8string: cstring) -> [^]win32.wchar_t ---
	utf16to8 :: proc(aUtf16string: [^]win32.wchar_t) -> cstring ---
	// Windows only utf-16 versions
	notifyPopupW :: proc(aTitle: [^]win32.wchar_t, aMessage: [^]win32.wchar_t, aIconType: [^]win32.wchar_t) -> c.int ---
	messageBoxW :: proc(aTitle: [^]win32.wchar_t, aMessage: [^]win32.wchar_t, aDialogType: [^]win32.wchar_t, aIconType: [^]win32.wchar_t, aDefaultButton: c.int) -> c.int ---
	inputBoxW :: proc(aTitle: [^]win32.wchar_t, aMessage: [^]win32.wchar_t, aDefaultInput: [^]win32.wchar_t) -> [^]win32.wchar_t ---
	saveFileDialogW :: proc(aTitle: [^]win32.wchar_t, aDefaultPathAndOrFile: [^]win32.wchar_t, aNumOfFilterPatterns: c.int, aFilterPatterns: [^]win32.wstring, aSingleFilterDescription: [^]win32.wchar_t) -> [^]win32.wchar_t ---
	openFileDialogW :: proc(aTitle: [^]win32.wchar_t, aDefaultPathAndOrFile: [^]win32.wchar_t, aNumOfFilterPatterns: c.int, aFilterPatterns: [^]win32.wstring, aSingleFilterDescription: [^]win32.wchar_t, aAllowMultipleSelects: c.int) -> [^]win32.wchar_t ---
	selectFolderDialogW :: proc(aTitle: [^]win32.wchar_t, aDefaultPath: [^]win32.wchar_t) -> [^]win32.wchar_t ---
	colorChooserW :: proc(aTitle: [^]win32.wchar_t, aDefaultHexRGB: [^]win32.wchar_t, aDefaultRGB: [^]c.uchar, aoResultRGB: [^]c.uchar) -> win32.wchar_t ---
}
