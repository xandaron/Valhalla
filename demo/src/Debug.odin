package Demo

import "base:runtime"
import logging "core:log"
import "core:mem"

log :: logging.log
logf :: logging.logf

createTrackingAllocator :: proc() -> mem.Allocator {
	tracker := new(mem.Tracking_Allocator)
	mem.tracking_allocator_init(tracker, context.allocator)
	return mem.tracking_allocator(tracker)
}

destroyTrackingAllocator :: proc(allocator: mem.Allocator) {
	tracker := (^mem.Tracking_Allocator)(allocator.data)
	if len(tracker.allocation_map) > 0 {
		logf(.Debug, "=== %v allocations not freed: ===", len(tracker.allocation_map))
		for _, entry in tracker.allocation_map {
			logf(.Debug, "- %v bytes @ %v", entry.size, entry.location)
		}
	}
	if len(tracker.bad_free_array) > 0 {
		logf(.Debug, "=== %v incorrect frees: ===", len(tracker.bad_free_array))
		for entry in tracker.bad_free_array {
			logf(.Debug, "- %p @ %v", entry.memory, entry.location)
		}
	}
	backing := tracker.backing
	mem.tracking_allocator_destroy(tracker)
	free(tracker, backing)
}

createLogger :: proc() -> logging.Logger {
	console := new(logging.Logger, runtime.heap_allocator())
	console^ = logging.create_console_logger(allocator = runtime.heap_allocator())
	return logging.Logger {
		procedure = fatalLoggerProc,
		data = console,
		lowest_level = console.lowest_level,
		options = console.options,
	}
}

destroyLogger :: proc(logger: logging.Logger) {
	console := (^logging.Logger)(logger.data)
	logging.destroy_console_logger(console^, runtime.heap_allocator())
	free(console, runtime.heap_allocator())
}

@(private = "file")
fatalLoggerProc :: proc(
	data: rawptr,
	level: logging.Level,
	text: string,
	options: logging.Options,
	location := #caller_location,
) {
	console := (^logging.Logger)(data)
	console.procedure(console.data, level, text, options, location)
	if level == .Fatal {
		panic("Fatal error! Check log for details.", location)
	}
}
