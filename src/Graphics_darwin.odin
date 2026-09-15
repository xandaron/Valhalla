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

// AppKit's live resize runs the main run loop in NSEventTrackingRunLoopMode, so the timer has to
// be added for the common modes rather than the default mode alone. It then lives for the whole
// process, which is what pollingEvents guards against.
@(private)
installModalLoopTimer :: proc(window: WindowHandle) {
	block := NS.Block_createGlobalWithParam(nil, modalLoopTimerFired)

	// NS.Timer_scheduledTimerWithTimeIntervalRepeatsBlock drops its interval argument, so the
	// selector is sent directly instead.
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
