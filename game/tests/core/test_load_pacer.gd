extends "res://tests/harness.gd"
# World construction yields to the renderer in slices, not in whole stages.
const LoadPacer = preload("res://scripts/core/load_pacer.gd")
var frames = 0

func _initialize() -> void:
	call_deferred("run")

func busy(microseconds: int) -> void:
	var until = Time.get_ticks_usec() + microseconds
	while Time.get_ticks_usec() < until:
		pass

func run() -> void:
	process_frame.connect(func(): frames += 1)
	await process_frame
	var before = frames
	for i in range(40):
		await LoadPacer.tick(self)
	check(frames - before <= 1, "a quick loop is not interrupted (%d frames)" % (frames - before))
	before = frames
	var longest = 0
	var last = Time.get_ticks_usec()
	for i in range(60):
		busy(3000)
		await LoadPacer.tick(self)
		longest = maxi(longest, Time.get_ticks_usec() - last)
		last = Time.get_ticks_usec()
	var slices = frames - before
	check(slices >= 8 and slices <= 20, "180 ms of work in small steps is spread over frames (%d)" % slices)
	check(longest < 60000, "no stretch blocks the frame for long (%d ms)" % (longest / 1000))
	print("LOAD PACER RESULT: %d checks, %d failures" % [checks, failures])
	finish()
