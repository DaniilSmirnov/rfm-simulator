extends RefCounted
# Time-sliced yielding for world construction. Building a stage is a few seconds
# of CPU work (on a phone, several times that); done in long stretches between
# frames it freezes the loading screen and the browser tab. Loops call
# `await LoadPacer.tick(tree)` often: it returns at once while the current slice
# is young, and lets one frame draw when the slice has used up SLICE_USEC, so no
# stretch blocks the main thread for much longer than a frame, whatever one
# iteration costs on this device.
const SLICE_USEC = 14000
static var _since = 0

static func tick(tree: SceneTree) -> void:
	if Time.get_ticks_usec() - _since < SLICE_USEC:
		return
	await tree.process_frame
	_since = Time.get_ticks_usec()
