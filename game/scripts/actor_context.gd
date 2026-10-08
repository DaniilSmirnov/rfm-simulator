extends RefCounted
# A command carries its actor explicitly; it never impersonates the local player.
var owner = ""
var position = Vector3.ZERO
var car_position = Vector3.ZERO
var heading = 0.0
var yaw = 0.0
var variant = 0
var speed = 0.0
var in_car = true
var beers = 0
var eat_time = -1.0
var drink_time = -1.0
var remote = false

func capture_local(game) -> void:
	owner = game.chair_owner()
	position = game.player_position()
	car_position = game.car.position
	heading = game.heading
	yaw = game.view_yaw
	variant = game.selected_car
	speed = game.speed
	in_car = game.in_car
	beers = game.beers
	eat_time = game.eat_time
	drink_time = game.drink_time

static func from_command(command: Dictionary, model: int):
	var actor = load("res://scripts/actor_context.gd").new()
	var state: Dictionary = command.state
	actor.owner = str(command.get("player", "guest"))
	actor.position = Vector3(state.pos[0], state.pos[1], state.pos[2])
	actor.car_position = Vector3(state.car[0], state.car[1], state.car[2])
	actor.heading = float(state.get("heading", 0))
	actor.yaw = float(state.yaw)
	actor.variant = model
	actor.speed = float(state.get("speed", 0))
	actor.in_car = state.in_car
	actor.beers = int(state.get("beers", 0))
	actor.remote = true
	return actor

func can_act() -> bool:
	return not in_car and beers < 30
