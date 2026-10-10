extends SceneTree
# Shared base for every functional test script (`extends "res://tests/harness.gd"`).
# One check() and one finish(), so results look the same in every test, and a
# watchdog: a GDScript runtime error aborts the running coroutine and would
# otherwise leave the test hanging until the runner's timeout. The runner
# passes `-- --watchdog=<seconds>` slightly below its own timeout.
var failures = 0
var checks = 0
var watchdog_seconds = 85.0
var _started_msec = Time.get_ticks_msec()
var _finished = false

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--watchdog="):
			watchdog_seconds = maxf(1.0, arg.trim_prefix("--watchdog=").to_float())

func check(ok: bool, title: String) -> void:
	checks += 1
	print(("PASS: " if ok else "FAIL: ") + title)
	if not ok:
		failures += 1
		push_error("FAIL: " + title)

# Ends the test: exit code 1 when any check failed.
func finish() -> void:
	_finished = true
	quit(1 if failures else 0)

func _process(_delta: float) -> bool:
	if not _finished and Time.get_ticks_msec() - _started_msec > watchdog_seconds * 1000.0:
		_finished = true
		print("FAIL: watchdog — test did not finish within %.0f s (script error or deadlock)" % watchdog_seconds)
		print("WATCHDOG RESULT: %d checks, %d failures before timeout" % [checks, failures + 1])
		quit(1)
	return false
