extends RefCounted
# The host owns the timetable. Guests display snapshots without spawning cars.
const Loc = preload("res://scripts/loc.gd")
const OPENING_SECONDS = 180.0
const TURNAROUND_SECONDS = 60.0
var pass_index = 1
var phase = "countdown"
var remaining = OPENING_SECONDS
var zero_index = 0
var active_id = -1
# An ambulance is on the stage: starts pause and crews brake until it leaves.
var red_flag = false

func update(game, delta: float) -> void:
	if not game.playing or game.paused or game.dead or game.finished or (game.room.is_guest()):
		return
	game.park_traffic.update(delta)
	match phase:
		"countdown", "intermission":
			remaining = maxf(0.0, remaining - delta)
			if remaining <= 0:
				if phase == "intermission":
					pass_index = 2
					game.rally_spawn_count = 0
					game.passed = 0
					game._cancel_tow()
					# Crews left on the stage are recovered to the park at its end.
					game.park_traffic.settle()
				phase = "opening_police"
				active_id = service_id(101)
				game.racing = true
				game.spawn_course_car("opening_police", active_id)
		"racing":
			game.race_clock += delta
			if red_flag:
				pass
			elif game.rally_spawn_count < game.RALLY_CREW_LIMIT:
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
					active_id = service_id(105)
					game.spawn_course_car("closing_police", active_id)

func vehicle_finished(game, id: int) -> void:
	if id != active_id:
		return
	active_id = -1
	match phase:
		"opening_police":
			phase = "zero"
			zero_index = 1
			active_id = service_id(102)
			game.spawn_course_car("zero", active_id, zero_index)
		"zero":
			if zero_index < 3:
				zero_index += 1
				active_id = service_id(101 + zero_index)
				game.spawn_course_car("zero", active_id, zero_index)
			else:
				phase = "racing"
				game.spawn_clock = 5.0
				game.toast("Нулевые экипажи прошли. Через 5 секунд стартуют гонщики!")
		"closing_police":
			if pass_index == 1:
				phase = "intermission"
				remaining = TURNAROUND_SECONDS
				game.toast("Первый проход завершён. Через минуту СУ откроется в обратную сторону.")
			else:
				phase = "complete"
				game.cancel_placement()
				game.toast("Оба прохода завершены. Соберите лагерь и езжайте в парк сервиса — на старте или на финише СУ.")

func service_id(base: int) -> int:
	return base + (pass_index - 1) * 200

func caption() -> String:
	return Loc.t("ПРОХОД %d/2 · %s · %s") % [pass_index, Loc.t("ОБРАТНО") if pass_index == 2 else Loc.t("ПРЯМО"), phase_caption()]

# The phone shows a shorter line: no direction, and the countdown reads "starts in".
func short_caption() -> String:
	var phase_text = phase_caption()
	if phase == "countdown" and not red_flag:
		var seconds = ceili(remaining)
		phase_text = Loc.t("СТАРТ ЧЕРЕЗ %02d:%02d") % [seconds / 60, seconds % 60]
	return Loc.t("СУ %d/2 · %s") % [pass_index, phase_text]

func phase_caption() -> String:
	if red_flag:
		return Loc.t("КРАСНЫЙ ФЛАГ · СКОРАЯ НА СУ")
	match phase:
		"countdown":
			var seconds = ceili(remaining)
			return Loc.t("ДО ОТКРЫТИЯ СУ %02d:%02d") % [seconds / 60, seconds % 60]
		"intermission":
			var seconds = ceili(remaining)
			return Loc.t("ДО ОБРАТНОГО ПРОХОДА %02d:%02d") % [seconds / 60, seconds % 60]
		"opening_police": return Loc.t("ОТКРЫТИЕ СУ · ПОЛИЦИЯ")
		"zero": return Loc.t("НУЛЕВОЙ ЭКИПАЖ %d/3 · № 0") % zero_index
		"racing": return Loc.t("СУ ОТКРЫТ · ГОНЩИКИ")
		"closing_police": return Loc.t("ЗАКРЫТИЕ СУ · ПОЛИЦИЯ")
		_: return Loc.t("СУ ЗАКРЫТ")

func snapshot() -> Dictionary:
	return {"pass_index": pass_index, "phase": phase, "remaining": ceilf(remaining), "zero_index": zero_index, "active_id": active_id, "red_flag": red_flag}

func apply_snapshot(data: Dictionary) -> void:
	pass_index = clampi(int(data.get("pass_index", 1)), 1, 2)
	phase = str(data.get("phase", "countdown"))
	remaining = clampf(float(data.get("remaining", OPENING_SECONDS)), 0, OPENING_SECONDS)
	zero_index = clampi(int(data.get("zero_index", 0)), 0, 3)
	active_id = int(data.get("active_id", -1))
	red_flag = data.get("red_flag", false) == true
