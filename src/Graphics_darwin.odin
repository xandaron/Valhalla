package Valhalla

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private = "file")
modalLoopTimerFired :: proc "c" (userData: rawptr, timer: ^NS.Timer) {
	if !pollingEvents {
		return
	}
	context = globals.runtimeContext
	tickFrame()
}

@(private)
installModalLoopTimer :: proc(window: WindowHandle) {
	block := NS.Block_createGlobalWithParam(nil, modalLoopTimerFired)

	timer := intrinsics.objc_send(
		^NS.Timer,
		NS.Timer,
		"scheduledTimerWithTimeInterval:repeats:block:",
		NS.TimeInterval(0.008),
		NS.BOOL(true),
		block,
	)

	NS.RunLoop_addTimerForMode(NS.RunLoop_mainRunLoop(), timer, NS.RunLoopCommonModes)
}
