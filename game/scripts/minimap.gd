extends Control
var game: Node

func _draw() -> void:
	if not is_instance_valid(game):
		return
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	for i in range(game.stage.points.size() - 1):
		draw_line(project(game.stage.points[i]), project(game.stage.points[i + 1]), Color("c4b48d"), 3, true)
	if game.camp != null:
		draw_circle(project(game.camp.position), 5, Color("efc66b"))
	for racer in game.racers:
		draw_circle(project(racer.node.position), 3, Color("d76646"))
	if game.room != null and game.room.connected:
		for peer in game.room.peers.values():
			if peer.state != null:
				draw_circle(project(game.room.v(peer.state.pos)), 4, Color("79cdd1"))
	var center = player_marker_position()
	var forward = player_direction()
	var side = Vector2(-forward.y, forward.x)
	var arrow = PackedVector2Array([center + forward * 11, center - forward * 6 + side * 5, center - forward * 6 - side * 5])
	draw_colored_polygon(arrow, Color("f2ead4"))
	arrow.append(arrow[0])
	draw_polyline(arrow, Color("17251b"), 2, true)

func player_marker_position() -> Vector2:
	var point = project(game.player_position())
	return point.clamp(Vector2.ONE * 12, size - Vector2.ONE * 12)

func player_direction() -> Vector2:
	var yaw = game.heading if game.in_car else game.view_yaw
	# Godot forward is -Z; map Y increases with world Z. Respect both map scales.
	return Vector2(-sin(yaw) * 0.6, -cos(yaw) * (size.y - 26) / RallyStage.LENGTH).normalized()

func project(p: Vector3) -> Vector2:
	return Vector2(size.x * 0.5 + p.x * 0.6, size.y - 12 + p.z / RallyStage.LENGTH * (size.y - 26))

func _background() -> StyleBoxFlat:
	var style = StyleBoxFlat.new()
	style.bg_color = Color("613b2ae8") if is_instance_valid(game) and game.stage.desert else Color("26352be8")
	style.set_corner_radius_all(12)
	return style
