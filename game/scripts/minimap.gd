extends Control
const StageRegistry = preload("res://scripts/stage_registry.gd")
const WATER_COLOR = Color("4f7f9c")
const WATER_DOT_RADIUS = 2.6
var game: Node
# Lakes are static: they are rasterised once per map size into one texture.
# Drawing every lake cell as its own circle cost one draw call per cell
# (~2 700 on «Финский лес», more than the whole 3D scene of other stages).
var water_texture: ImageTexture
var water_key = ""
var background: StyleBoxFlat

func _draw() -> void:
	if not is_instance_valid(game):
		return
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	var water = _water_texture()
	if water != null:
		draw_texture(water, Vector2.ZERO)
	for i in range(game.stage.points.size() - 1):
		draw_line(project(game.stage.points[i]), project(game.stage.points[i + 1]), Color("c4b48d"), 3, true)
	var parks = game.stage.parks
	for index in range(parks.ends.size()):
		var corners = PackedVector2Array()
		for corner in [Vector2(-parks.HALF_WIDTH, parks.LANE), Vector2(parks.HALF_WIDTH, parks.LANE), Vector2(parks.HALF_WIDTH, parks.LANE + parks.DEPTH), Vector2(-parks.HALF_WIDTH, parks.LANE + parks.DEPTH)]:
			corners.append(project(parks.world(index, corner.x, corner.y)))
		draw_colored_polygon(corners, Color("c4b48d"))
		draw_line(project(parks.world(index, 0, 0)), project(parks.world(index, 0, parks.LANE)), Color("c4b48d"), 3, true)
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
	var yaw = game.rides.heading() if game.in_car else game.view_yaw
	# Godot forward is -Z; map Y increases with world Z. Respect both map scales.
	return Vector2(-sin(yaw) * 0.6, -cos(yaw) * (size.y - 26) / _span()).normalized()

# The stage and its two service parks fill the map from top to bottom.
func _span() -> float:
	var limits: Vector2 = game.stage.parks.z_limits
	return maxf(1.0, limits.y - limits.x)

func project(p: Vector3) -> Vector2:
	return Vector2(size.x * 0.5 + p.x * 0.6, size.y - 12 - (game.stage.parks.z_limits.y - p.z) / _span() * (size.y - 26))

func _water_texture() -> ImageTexture:
	var water = game.stage.water
	if water == null or water.minimap_cells.is_empty():
		return null
	var width = int(ceil(size.x))
	var height = int(ceil(size.y))
	if width <= 0 or height <= 0:
		return null
	var key = "%d:%dx%d:%d" % [water.get_instance_id(), width, height, water.minimap_cells.size()]
	if key == water_key and water_texture != null:
		return water_texture
	# Same dots as before, stamped by the engine instead of drawn one by one.
	# Overlapping dots used to stack to near-opaque water; the stamped dots
	# saturate the same way and keep soft edges at the shore.
	var image = Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	var brush = _water_brush()
	var half = brush.get_width() / 2
	var brush_rect = Rect2i(Vector2i.ZERO, brush.get_size())
	for cell in water.minimap_cells:
		var center = project(Vector3(cell.x, 0, cell.y))
		image.blend_rect(brush, brush_rect, Vector2i(roundi(center.x) - half, roundi(center.y) - half))
	water_texture = ImageTexture.create_from_image(image)
	water_key = key
	return water_texture

# Antialiased dot of WATER_DOT_RADIUS in the opaque water colour.
func _water_brush() -> Image:
	var reach = int(ceil(WATER_DOT_RADIUS + 0.5))
	var side = reach * 2 + 1
	var brush = Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
	var center = Vector2(reach + 0.5, reach + 0.5)
	for y in range(side):
		for x in range(side):
			var edge = clampf(WATER_DOT_RADIUS + 0.5 - center.distance_to(Vector2(x + 0.5, y + 0.5)), 0.0, 1.0)
			brush.set_pixel(x, y, Color(WATER_COLOR, edge))
	return brush

func _background() -> StyleBoxFlat:
	var color = Color(str(StageRegistry.value(game.stage.variant, "minimap"))) if is_instance_valid(game) else Color("26352be8")
	if background == null:
		background = StyleBoxFlat.new()
		background.set_corner_radius_all(12)
	background.bg_color = color
	return background
