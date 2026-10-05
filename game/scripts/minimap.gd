extends Control
var game: Node

func _draw() -> void:
	if not is_instance_valid(game):
		return
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for i in range(game.stage.points.size() - 1):
		draw_line(project(game.stage.points[i]), project(game.stage.points[i + 1]), Color("c4b48d"), 3, true)
	for i in range(game.stage.clearings.size()):
		var p = project(game.stage.clearings[i])
		draw_circle(p, 5, Color("c57843") if i == game.target_clearing else Color("829080"))
	if game.camp != null:
		draw_circle(project(game.camp.position), 5, Color("efc66b"))
	for racer in game.racers:
		draw_circle(project(racer.node.position), 3, Color("d76646"))
	if game.room != null and game.room.connected:
		for peer in game.room.peers.values():
			if peer.state != null:
				draw_circle(project(game.room.v(peer.state.pos)), 4, Color("79cdd1"))
	draw_circle(project(game.player_position()), 5, Color("f2ead4"))
	var heading = Vector2(-sin(game.heading), cos(game.heading))
	draw_line(project(game.player_position()), project(game.player_position()) + heading * 12, Color("f2ead4"), 2)

func project(p: Vector3) -> Vector2:
	return Vector2(size.x * 0.5 + p.x * 0.6, size.y - 12 + p.z / RallyStage.LENGTH * (size.y - 26))

func _background() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("26352be8")
	style.set_corner_radius_all(12)
	return style
