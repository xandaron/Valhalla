package Valhalla

import "base:runtime"
import logging "core:log"
import vk "vendor:vulkan"

VK_DEBUG_MESSENGER_CREATE_INFO := vk.DebugUtilsMessengerCreateInfoEXT {
	sType           = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
	pNext           = nil,
	messageSeverity = {.ERROR, .WARNING, .INFO},
	messageType     = {.GENERAL, .PERFORMANCE, .VALIDATION},
	pfnUserCallback = vkDebugCallback,
	pUserData       = nil,
}

log :: proc(level: logging.Level, args: ..any, sep := " ", location := #caller_location) {
	logging.log(level, ..args, sep = sep, location = location)
	if level == .Fatal {
		panic("Fatal error! Check log for details.")
	}
}

logf :: proc(level: logging.Level, fmt_str: string, args: ..any, location := #caller_location) {
	logging.logf(level, fmt_str, ..args, location = location)
	if level == .Fatal {
		panic("Fatal error! Check log for details.")
	}
}

// GLFW
glfwErrorCallback :: proc "c" (code: i32, desc: cstring) {
	context = globals.runtimeContext
	logf(.Error, "GLFW Error: Code %d, Description: %s", code, string(desc))
}

// Vulkan
vkDebugCallback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageType: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = globals.runtimeContext
	logf(
		vkDecodeSeverity(messageSeverity),
		"[Vulkan - %s]:\n%s",
		vkDecodeMessageTypeFlag(messageType),
		pCallbackData.pMessage,
	)
	return false
}

vkDecodeSeverity :: proc(messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT) -> logging.Level {
	if .ERROR in messageSeverity {
		return .Error
	} else if .WARNING in messageSeverity {
		return .Warning
	} else if .INFO in messageSeverity {
		return .Info
	} else if .VERBOSE in messageSeverity {
		return .Debug
	}
	panic("Invalid message severity!")
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
	context = globals.runtimeContext
	if int(err) == 0 {
		return
	}
	if int(err) < 0 {
		logf(.Error, "[Imgui-Vulkan] Fatal: VkResult = %v", err)
		panic("Imgui error")
	}
	logf(.Error, "[Imgui-Vulkan] Error: VkResult = %v", err)
}

