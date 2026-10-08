extends "res://scripts/game.gd"
var timings = {}
func record(key: String, started: int):
 if not timings.has(key): timings[key] = []
 timings[key].append(Time.get_ticks_usec()-started)
func _drive(delta: float) -> void:
 var t=Time.get_ticks_usec()
 super._drive(delta)
 record("_drive", t)
func _walk(delta: float) -> void:
 var t=Time.get_ticks_usec()
 super._walk(delta)
 record("_walk", t)
func _update_hud() -> void:
 var t=Time.get_ticks_usec()
 super._update_hud()
 record("_update_hud", t)
func _update_racers(delta: float) -> void:
 var t=Time.get_ticks_usec()
 super._update_racers(delta)
 record("_update_racers", t)
func _update_stones(delta: float) -> void:
 var t=Time.get_ticks_usec()
 super._update_stones(delta)
 record("_update_stones", t)
func _update_camera(delta: float) -> void:
 var t=Time.get_ticks_usec()
 super._update_camera(delta)
 record("_update_camera", t)
