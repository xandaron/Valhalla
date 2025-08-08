package Valhalla

import "base:runtime"
import "core:fmt"
import vk "vendor:vulkan"


VK_DEBUG_MESSENGER_CREATE_INFO :: vk.DebugUtilsMessengerCreateInfoEXT {
	sType           = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
	pNext           = nil,
	messageSeverity = {.ERROR, .WARNING, .INFO},
	messageType     = {.GENERAL, .PERFORMANCE, .VALIDATION},
	pfnUserCallback = vkDebugCallback,
	pUserData       = nil,
}

// GLFW
glfwErrorCallback :: proc "c" (code: i32, desc: cstring) {
	context = runtime.default_context()
	fmt.printfln("[GLFW Error]: Code %d, Description: %s", code, string(desc))
}

// Error Callback
valhallaErrLevelToLogErrLevel :: proc(level: ErrorLevel) -> string {
	switch level {
	case .Warning:
		return "Warning"
	case .Error:
		return "Error"
	case .Fatal:
		return "Fatal"
	}
	panic("Unknown error level!")
}

errorCallback: ErrorCallback : proc(level: ErrorLevel, message: string) {
	fmt.printfln("[%s]: %s", valhallaErrLevelToLogErrLevel(level), message)
}

// Vulkan
vkDebugCallback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageType: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()
	fmt.printfln(
		"[%s] Vulkan validation layer (%s):\n%s\n",
		vkDecodeSeverity(messageSeverity),
		vkDecodeMessageTypeFlag(messageType),
		pCallbackData.pMessage,
	)
	return false
}

vkDecodeSeverity :: proc(
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
) -> string {
	if vk.DebugUtilsMessageSeverityFlagEXT.VERBOSE in messageSeverity {
		return "Info"
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.INFO in messageSeverity {
		return "Debug"
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.WARNING in messageSeverity {
		return "Warning"
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.ERROR in messageSeverity {
		return "Error"
	}
	panic("Unknown severity type!")
}

vkDecodeSeverityString :: proc(messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT) -> string {
	if vk.DebugUtilsMessageSeverityFlagEXT.VERBOSE in messageSeverity {
		return "Info"
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.INFO in messageSeverity {
		return "Debug"
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.WARNING in messageSeverity {
		return "Warning"
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.ERROR in messageSeverity {
		return "Error"
	}
	panic("Unknown severity type!")
}

vkDecodeMessageTypeFlag :: proc(messageType: vk.DebugUtilsMessageTypeFlagsEXT) -> string {
	if .GENERAL in messageType {
		return "General"
	}
	if .VALIDATION in messageType {
		return "Validation"
	}
	if .PERFORMANCE in messageType {
		return "Performance"
	}
	return "Unknown"
}

// Imgui Vulkan
imguiCheckVkResult :: proc "c" (err: vk.Result) {
	context = runtime.default_context()
	if int(err) == 0 {return}
	if int(err) < 0 {
		fmt.printfln("[Imgui-Vulkan] Fatal: VkResult = %v", err)
		panic("Imgui error")
	}
	fmt.printfln("[Imgui-Vulkan] Error: VkResult = %v", err)
}
