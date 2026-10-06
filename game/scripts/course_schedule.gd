extends RefCounted
# The host owns the timetable. Guests display snapshots without spawning cars.
const OPENING_SECONDS = 180.0
var phase = "countdown"
var remaining = OPENING_SECONDS
var zero_index = 0
var active_id = -1

func update(game, delta: float) -> void:
	if not game.playing or game.paused or game.dead or game.finished or (game.room.connected and not game.room.is_host):
		return
	match phase:
		"countdown":
			remaining = maxf(0.0, remaining - delta)
			if remaining <= 0:
				phase = "opening_police"
				active_id = 101
				game.racing = true
				game.spawn_course_car("opening_police", active_id)
		"racing":
			game.race_clock += delta
			if game.rally_spawn_count < game.RALLY_CREW_LIMIT:
				game.spawn_clock -= delta
				if game.spawn_clock <= 0:
					game.spawn_racer()
					game.spawn_clock = game.rng.randf_range(17, 23)
			elif game.passed >= game.RALLY_CREW_LIMIT:
				var moving = false
				for racer in game.racers:
					moving = moving or racer.state in ["racing", "offroad", "rock_bounce"]
				if not moving:
					phase = "closing_police"
					active_id = 105
					game.spawn_course_car("closing_police", active_id)

func vehicle_finished(game, id: int) -> void:
	if id != active_id:
		return
	active_id = -1
	match phase:
		"opening_police":
			phase = "zero"
			zero_index = 1
			active_id = 102
			game.spawn_course_car("zero", active_id, zero_index)
		"zero":
			if zero_index < 3:
				zero_index += 1
				active_id = 101 + zero_index
				game.spawn_course_car("zero", active_id, zero_index)
			else:
				phase = "racing"
				game.spawn_clock = 5.0
				game.toast("Нулевые экипажи прошли. Через 5 секунд стартуют гонщики!")
		"closing_police":
			phase = "complete"
			game.toast("Замыкающая полиция прошла. СУ закрыт.")

func caption() -> String:
	match phase:
		"countdown":
			var seconds = ceili(remaining)
			return "ДО ОТКРЫТИЯ СУ %02d:%02d" % [seconds / 60, seconds % 60]
		"opening_police": return "ОТКРЫТИЕ СУ · ПОЛИЦИЯ"
		"zero": return "НУЛЕВОЙ ЭКИПАЖ %d/3 · № 0" % zero_index
		"racing": return "СУ ОТКРЫТ · ГОНЩИКИ"
		"closing_police": return "ЗАКРЫТИЕ СУ · ПОЛИЦИЯ"
		_: return "СУ ЗАКРЫТ"

func snapshot() -> Dictionary:
	return {"phase": phase, "remaining": remaining, "zero_index": zero_index, "active_id": active_id}

func apply_snapshot(data: Dictionary) -> void:
	phase = str(data.get("phase", "countdown"))
	remaining = clampf(float(data.get("remaining", OPENING_SECONDS)), 0, OPENING_SECONDS)
	zero_index = clampi(int(data.get("zero_index", 0)), 0, 3)
	active_id = int(data.get("active_id", -1))
