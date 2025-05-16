#+private file

package Valhalla

import "base:runtime"

import "core:fmt"
import "core:log"
import "core:math"
import "core:os"
import t "core:time"
import dt "core:time/datetime"
import vk "vendor:vulkan"


@(private = "package")
createLogPath :: proc() -> string {
	if !os.exists("./logs") do os.make_directory("./logs")

	// Maybe I can check how many files are in the directory and then create a new file with the next number.
	now := t.now()
	year, month, day := t.date(now)
	dateTime: dt.DateTime = {
		date = dt.Date{year = (i64)(year), month = (i8)(month), day = (i8)(day)},
	}
	midnight, _ := t.datetime_to_time(dateTime)
	seconds := math.floor(t.duration_seconds(t.diff(midnight, now)))

	hours := math.floor(seconds / t.SECONDS_PER_HOUR)
	seconds -= hours * t.SECONDS_PER_HOUR
	minutes := math.floor(seconds / t.SECONDS_PER_MINUTE)
	seconds -= minutes * t.SECONDS_PER_MINUTE

	str: string = fmt.tprintf(
		"./logs/{:4i}{:2i}{:2i}{:2.0f}{:2.0f}{:2.0f}.log",
		dateTime.year,
		dateTime.month,
		dateTime.day,
		hours,
		minutes,
		seconds,
	)
	return str
}


//########################################################//
//                          GLFW                          //
//########################################################//


@(private = "package")
glfwErrorCallback :: proc "c" (code: i32, desc: cstring) {
	context = runtime.default_context()
	context.logger = logger
	log.logf(.Error, "[GLFW Error]: {}", string(desc))
}


//########################################################//
//                         Vulkan                         //
//########################################################//


@(private = "package")
vkDebugCallback :: proc "system" (
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
	messageType: vk.DebugUtilsMessageTypeFlagsEXT,
	pCallbackData: ^vk.DebugUtilsMessengerCallbackDataEXT,
	pUserData: rawptr,
) -> b32 {
	context = runtime.default_context()
	context.logger = logger
	log.logf(
		vkDecodeSeverity(messageSeverity),
		"Vulkan validation layer ({}):\n{}\n",
		vkDecodeMessageTypeFlag(messageType),
		pCallbackData.pMessage,
	)
	return false
}

@(private = "package")
vkDecodeSeverity :: proc(
	messageSeverity: vk.DebugUtilsMessageSeverityFlagsEXT,
) -> runtime.Logger_Level {
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

@(private = "package")
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

@(private = "package")
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

@(private = "package")
vkSetupDebugMessenger :: proc(graphicsContext: ^GraphicsContext) {
	createInfo := vkPopulateDebugMessengerCreateInfo()
	if vk.CreateDebugUtilsMessengerEXT(
		   graphicsContext^.instance,
		   &createInfo,
		   nil,
		   &graphicsContext^.debugMessenger,
	   ) !=
	   .SUCCESS {
		log.log(.Warning, "Failed to create vulkan debug callback!")
	}
}

@(private = "package")
vkPopulateDebugMessengerCreateInfo :: proc() -> (createInfo: vk.DebugUtilsMessengerCreateInfoEXT) {
	createInfo = {
		sType           = vk.StructureType.DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		pNext           = nil,
		messageSeverity = {.ERROR, .WARNING, .INFO},
		messageType     = {.GENERAL, .PERFORMANCE, .VALIDATION},
		pfnUserCallback = vkDebugCallback,
		pUserData       = nil,
	}
	return
}


//########################################################//
//                          Imgui                         //
//########################################################//


@(private = "package")
imguiCheckVkResult :: proc "c" (err: vk.Result) {
	context = runtime.default_context()
	logger = context.logger
	if int(err) == 0 { return }
	if int(err) < 0 {
		log.logf(.Fatal, "Imgui-Vulkan: VkResult = {}", err)
		panic("Imgui error")
	}
	log.logf(.Error, "Imgui-Vulkan: VkResult = {}", err)
}
