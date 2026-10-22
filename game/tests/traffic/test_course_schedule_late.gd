extends "res://tests/traffic/test_course_schedule.gd"
# The remaining maps of test_course_schedule.gd.

func stages() -> Array:
	return range(4, RallyStage.STAGES.size())

func checks_guest() -> bool:
	return false
