package Demo

import "base:runtime"
import "core:log"
import valhalla "../valhalla"
import vk "vendor:vulkan"


// GLFW
glfwErrorCallback :: proc "c" (code: i32, desc: cstring) {
	context = globals.runtimeContext
	log.logf(.Error, "[GLFW Error]: {}", string(desc))
}

// Error Callback
valhallaErrLevelToLogErrLevel :: proc(level: valhalla.ErrorLevel) -> log.Level {
	switch level {
	case .Warning:
		return .Warning
	case .Error:
		return .Error
	case .Fatal:
		return .Fatal
	}
	panic("Unknown error level!")
}

errorCallback: valhalla.ErrorCallback : proc(level: valhalla.ErrorLevel, message: string) {
	log.log(valhallaErrLevelToLogErrLevel(level), message)
}

// Vulkan
vkDebugCallback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageType: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = globals.runtimeContext
	log.logf(
		vkDecodeSeverity(messageSeverity),
		"Vulkan validation layer (%s):\n{}\n",
		vkDecodeMessageTypeFlag(messageType),
		pCallbackData.pMessage,
	)
	return false
}

vkDecodeSeverity :: proc(
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
) -> log.Level {
	if vk.DebugUtilsMessageSeverityFlagEXT.VERBOSE in messageSeverity {
		return .Info
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.INFO in messageSeverity {
		return .Debug
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.WARNING in messageSeverity {
		return .Warning
	}
	if vk.DebugUtilsMessageSeverityFlagEXT.ERROR in messageSeverity {
		return .Error
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
	context = globals.runtimeContext
	if int(err) == 0 {return}
	if int(err) < 0 {
		log.logf(.Fatal, "Imgui-Vulkan: VkResult = %v", err)
		panic("Imgui error")
	}
	log.logf(.Error, "Imgui-Vulkan: VkResult = %v", err)
}
