package Valhalla

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import "vendor:glfw"

@(private = "file")
MODAL_LOOP_INTERVAL :: NS.TimeInterval(0.008)

@(private = "file")
modal_loop_timer: ^NS.Timer

@(private = "file")
modal_loop_timer_fired :: proc "c" (user_data: rawptr, timer: ^NS.Timer) {
	if !polling_events {
		return
	}
	context = runtime_context
	request_frame()
}

@(private)
install_modal_loop_timer :: proc(handle: glfw.WindowHandle) {
	if modal_loop_timer != nil {
		return
	}
	block := NS.Block_createGlobalWithParam(nil, modal_loop_timer_fired)
	modal_loop_timer = intrinsics.objc_send(
		^NS.Timer,
		NS.Timer,
		"scheduledTimerWithTimeInterval:repeats:block:",
		MODAL_LOOP_INTERVAL,
		NS.BOOL(true),
		block,
	)
	NS.RunLoop_addTimerForMode(NS.RunLoop_mainRunLoop(), modal_loop_timer, NS.RunLoopCommonModes)
}
