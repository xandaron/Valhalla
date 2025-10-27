package Valhalla

import "base:runtime"
import "core:fmt"
import logging "core:log"
import vk "vendor:vulkan"

VK_DEBUG_MESSENGER_CREATE_INFO :: vk.DebugUtilsMessengerCreateInfoEXT {
	sType           = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
	pNext           = nil,
	messageSeverity = {.ERROR, .WARNING, .INFO},
	messageType     = {.GENERAL, .PERFORMANCE, .VALIDATION},
	pfnUserCallback = vkDebugCallback,
	pUserData       = nil,
}

log :: logging.log
logf :: logging.logf

// GLFW
glfwErrorCallback :: proc "c" (code: i32, desc: cstring) {
	context = runtime.default_context()
	logf(.Error, "GLFW Error: Code %d, Description: %s", code, string(desc))
}

// Vulkan
vkDebugCallback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageType: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()
	logf(
		.Error,
		"[%s] Vulkan validation layer (%s):\n%s",
		vkDecodeSeverity(messageSeverity),
		vkDecodeMessageTypeFlag(messageType),
		pCallbackData.pMessage,
	)
	return false
}

vkDecodeSeverity :: proc(messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT) -> string {
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
		logf(.Error, "[Imgui-Vulkan] Fatal: VkResult = %v", err)
		panic("Imgui error")
	}
	logf(.Error, "[Imgui-Vulkan] Error: VkResult = %v", err)
}
