extends RefCounted
# Single lifecycle; pause causes are independent and cannot cancel one another.
enum Phase { MENU, LOADING, PLAYING, DEAD, FINISHED }
var phase = Phase.MENU
var world_ready = false
var pause_causes: Dictionary = {}

var playing: bool:
	get: return phase in [Phase.PLAYING, Phase.DEAD, Phase.FINISHED]
	set(value):
		if value and phase in [Phase.MENU, Phase.LOADING]: phase = Phase.PLAYING
		elif not value: phase = Phase.MENU
var loading: bool:
	get: return phase == Phase.LOADING
	set(value):
		if value: phase = Phase.LOADING
		elif phase == Phase.LOADING: phase = Phase.MENU
var dead: bool:
	get: return phase == Phase.DEAD
	set(value):
		if value: phase = Phase.DEAD
		elif phase == Phase.DEAD: phase = Phase.PLAYING
var finished: bool:
	get: return phase == Phase.FINISHED
	set(value):
		if value: phase = Phase.FINISHED
		elif phase == Phase.FINISHED: phase = Phase.PLAYING

func set_pause(cause: String, enabled: bool) -> void:
	if enabled: pause_causes[cause] = true
	else: pause_causes.erase(cause)

func simulating() -> bool:
	return phase == Phase.PLAYING and pause_causes.is_empty()

func can_act() -> bool:
	return simulating()
