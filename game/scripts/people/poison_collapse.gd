extends RefCounted
# Poisonous mushrooms (fly agaric, toadstool): besides the inverted colours the
# player collapses where they stand and an ambulance comes, as for a person hit
# by a car (injuries.gd): red flag, medics, then a limp. Host only; guests see
# it in the injuries snapshot, where the record carries "cause": "poison".
const Loc = preload("res://scripts/ui/loc.gd")
const TOAST = "Отравление грибами! Ты упал — скорая уже выехала со старта."
const ANNOUNCE = "Участник компании отравился грибами! Красный флаг, вызвана скорая."

static func collapse(injuries, key: String, feet: Vector3) -> bool:
	var game = injuries.game
	if not injuries.authority() or injuries.is_down(key):
		return false
	var spot = Vector3(feet.x, game.stage.ground(feet), feet.z)
	var record = {"phase": "lying", "cause": "poison", "time": 0.0, "pos": spot + Vector3(0, 0.25, 0), "rot": Vector3(0, game.actor_yaw(), PI / 2),
		"start": spot, "station": game.race_station(spot), "treat": 0.0, "limp": 0.0, "ambulance": -1}
	injuries.records[key] = record
	injuries._assign(record, key)
	game.course.red_flag = true
	if key == injuries.local_key():
		injuries._go_down()
		game.toast(TOAST)
	else:
		game.announce(ANNOUNCE)
	return true

# HUD status of a casualty waiting for the ambulance (metres to go, -1 before
# it left), hit or poisoned.
static func waiting_line(record: Dictionary, metres: float) -> String:
	if str(record.get("cause", "")) == "poison":
		return Loc.t("ОТРАВЛЕНИЕ · СКОРАЯ В ПУТИ · %d М") % int(metres) if metres >= 0.0 else Loc.t("ОТРАВЛЕНИЕ · СКОРАЯ ВЫЕЗЖАЕТ")
	return Loc.t("ТЕБЯ СБИЛИ · СКОРАЯ В ПУТИ · %d М") % int(metres) if metres >= 0.0 else Loc.t("ТЕБЯ СБИЛИ · СКОРАЯ ВЫЕЗЖАЕТ")
