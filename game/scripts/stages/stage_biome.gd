extends RefCounted
# The contract of a special stage (СУ). stage.gd owns the shared machinery —
# route index, terrain and road meshes, forest, collisions, collectibles,
# officials — and asks the stage's biome for everything that differs between
# stages. A biome overrides only what it changes; the defaults describe a plain
# gravel forest stage. Stages are listed in res://data/stages.json, which also
# holds their sky, sun, loading caption and minimap tint.
#
# A new stage: subclass this file, implement route() and whatever differs,
# add one entry to stages.json and one product to store_catalog.json.

var stage # RallyStage that owns this biome; set by attach()

func attach(owner) -> void:
	stage = owner

# ---------------------------------------------------------------- features
# Shared subsystems a stage switches on, instead of checks of its identity.

# Deep snow, snowbanks, digging and the shovel (deep_snow.gd, snowbanks.gd).
func has_snow() -> bool:
	return false

# What people wear here (character_profiles.gd OUTFITS; "" summer clothes):
# players, peers, spectators, officials, villagers, the medic and
# first-person hands. Snowy stages dress for winter.
func outfit() -> String:
	return "winter" if has_snow() else ""

# Lakes: buoyancy, wading, splashes (water.gd). Return the Water instance.
func make_water():
	return null

# ---------------------------------------------------------------- route

# Length of the stage road in metres (stations 0..route_length()). Most stages
# share the default; a longer one also widens world_bounds() to hold it.
func route_length() -> float:
	return 840.0

# The rectangle of land that is built, walked and driven on (x, z in metres).
func world_bounds() -> Rect2:
	return Rect2(-204.0, -920.0, 408.0, 1000.0)

# Centre line of the road at station s (metres along the route).
func route(s: float) -> Vector3:
	return Vector3(0.0, 0.0, -s)

# True when the route winds back on itself (corners, hairpins): stations are then
# found by searching the indexed route instead of reading -z, and at() samples
# route() directly.
func winding_route() -> bool:
	return false

# Called once the route points exist: spectator clearings, trails, reserved spots.
func configure() -> void:
	pass

# ---------------------------------------------------------------- ground

# Analytic height of the land at pos, before snow; shared by tyres, feet, camps
# and the rendered terrain.
func base_ground(pos: Vector3) -> float:
	var s = stage.road_s(pos)
	var p = stage.at(s)
	var distance = stage.road_distance(pos)
	var slope = maxf(0, distance - 10.0)
	var height = p.y + roughness(s) * (1.0 - smoothstep(3.7, 8.0, distance)) + sin(pos.x * 0.07 + s * 0.013) * slope * 0.08 + slope * 0.20
	height += land_relief(pos, distance)
	height = stage.blend_clearings(pos, height, 5.5, 11.5)
	return stage.blend_trails(pos, height)

# Small bumps of the road surface along the route (default land only).
func roughness(_s: float) -> float:
	return 0.0

# Hills and ditches added to the default land.
func land_relief(_pos: Vector3, _distance: float) -> float:
	return 0.0

# Top surface people and objects stand on (snow floors, snowbanks).
func ground(pos: Vector3) -> float:
	return stage.base_ground(pos)

# Tyres rest on what is drawn: the road ribbon follows ground() across the
# carriageway, but beyond its edge the land mesh lies about 0.25 m lower
# (terrain vertices are cut below ground(), see Stage.terrain_surface_height).
# Blend over half a metre past the edge so a wheel rolls off the road.
func vehicle_ground(pos: Vector3) -> float:
	var height = stage.ground(pos)
	var past_edge = stage.road_distance(pos) - stage.road_width(stage.road_s(pos)) * 0.5
	if past_edge <= 0.0:
		return height
	return lerpf(height, minf(height, stage.terrain_surface_height(pos)), smoothstep(0.0, 0.5, past_edge))

func walking_ground(pos: Vector3) -> float:
	return stage.ground(pos)

# Height a walker's feet rest at (jetty decks, swimming); `height` is the ground.
func walk_floor(_pos: Vector3, height: float) -> float:
	return height

# Extra walking obstacles of the stage (cliff lips) at the next foot position.
func walk_blocked(_next: Vector3, _feet_height: float) -> bool:
	return false

# Whether a car is stopped moving from `from` to `to`, e.g. by a rock face
# too steep for tyres to climb. Same answer for the host and every guest.
func drive_blocked(_from: Vector3, _to: Vector3) -> bool:
	return false

# Height share (0..1) of the ploughed snowbanks at station s, e.g. 0 on a bridge.
func snowbank_mask(_s: float) -> float:
	return 1.0

# Whether camp furniture of this kind may stand at spot (dry, level, dug out).
func camp_allowed(_spot: Vector3, _kind: String) -> bool:
	return true

# ---------------------------------------------------------------- terrain mesh

# Size of the terrain triangles around a 4 m cell centre: 1, 2 or 4 m.
func terrain_tile_step(_p: Vector3) -> float:
	return 4.0

# Height of a rendered terrain vertex. The default snaps fine roadside tiles to
# the coarse neighbouring edges so no cracks open at T-junctions.
func terrain_vertex_height(x: float, z: float) -> float:
	return stage.snapped_vertex_height(x, z)

# Split the terrain into 64 m tiles (snow deformation, culling of big maps).
func terrain_tiled() -> bool:
	return false

# Memoise tile steps and vertex heights during the build (expensive ground()).
func cache_terrain() -> bool:
	return false

func terrain_color(_v: Vector3) -> Color:
	return Color(0.32, 0.38, 0.25)

# A finished terrain tile, e.g. registered for snow deformation.
func terrain_chunk_built(_tile: Vector2i, _node: MeshInstance3D) -> void:
	pass

# ---------------------------------------------------------------- road

func road_width(_s: float) -> float:
	return stage.WIDTH

# Colour of a road vertex p on the segment that starts at station s.
func road_color(p: Vector3, _s: float) -> Color:
	var base = Color("9d896b")
	var shade = sin(p.x * 0.17 + p.z * 0.11) * 0.025 + sin(p.z * 0.29 - p.x * 0.07) * 0.015
	return base.lightened(shade)

# Surface kind of the road at s; each kind becomes its own mesh and material.
func road_surface_kind(_s: float) -> String:
	return "default"

# Material of a road surface kind; null keeps vertex colours.
func road_material(_kind: String) -> StandardMaterial3D:
	return null

# Lateral strips of the road mesh (more strips follow a cambered surface).
func road_strips() -> int:
	return 4

# An earth shoulder mesh between the road edge and the terrain.
func road_seam_shoulders() -> bool:
	return false

# Muddy wheel tracks and puddles at station s: dug into the road itself, as
# relief for tyres and feet and in the road mesh (road_relief.gd).
func road_ruts(_s: float) -> bool:
	return false

# How deep the ruts are at s, 0..1; a stage fades them out smoothly where it
# stops (a ford) so the road has no step. The default follows road_ruts().
func rut_strength(s: float) -> float:
	return 1.0 if road_ruts(s) else 0.0

# Lateral breakpoints of the road mesh across `width`, and how many segments one
# metre of route is cut into; a road with ruts is cut finer.
func road_edges(width: float) -> Array:
	return stage.relief.edges(width, road_strips())

func road_divisions(length: float) -> int:
	return stage.relief.divisions(length)

func after_road(_cooperative: bool = false) -> void:
	pass

# ---------------------------------------------------------------- driving

func grip(pos: Vector3) -> float:
	if stage.road_distance(pos) > stage.WIDTH * 0.55:
		return 0.48
	return 0.42 if int(stage.road_s(pos) / stage.STEP) % 13 == 7 else 0.78

# Target speed of rally crews at s, m/s.
func rally_speed(_s: float) -> float:
	return 27.0

# Station range (start, end) where a crew's nerve decides whether it lifts
# for an abrupt drop or carries its speed over it; empty when there is none.
func jump_zone() -> Vector2:
	return Vector2.ZERO

# How far beyond the road edge crews may run when cutting or overtaking.
func shoulder(_s: float) -> float:
	return 1.4

# Loose surfaces throw gravel from spinning tyres.
func loose_surface(_pos: Vector3) -> bool:
	return true

# What boots sound like at pos: "gravel", "asphalt", "snow" or "grass"
# (game/audio step-* sounds).
func surface_sound(pos: Vector3) -> String:
	return "gravel" if stage.road_distance(pos) <= stage.WIDTH * 0.55 else "grass"

# Crews follow pre-recorded runs (baked rally tracks) on this stage.
func uses_baked_tracks() -> bool:
	return false

# ---------------------------------------------------------------- scenery

# Conifers planted by stage.gd's shared forest generator; 0 for no forest.
func forest_tree_count() -> int:
	return 0

func forest_tree_max_height() -> float:
	return 17.0

# Trees keep this far from spectator clearings.
func forest_clearing_radius() -> float:
	return 8.5

# Stage-specific places where no tree may grow (paths, buildings, water, rock).
func tree_blocked(p: Vector3) -> bool:
	return stage.trail_distance(p) < 3.2

func roadside_rock_blocked(_p: Vector3) -> bool:
	return false

# Stage-specific places the woodland floor generator must keep clear.
func woodland_blocked(_pos: Vector3, _padding: float) -> bool:
	return false

# Stage scenery after terrain, road and forest. May await when cooperative.
func build_details(_cooperative: bool) -> void:
	pass

# Signposts at the spectator clearings ("ПОЛЯНА N").
func clearing_signs() -> bool:
	return true

# Distant mountains or ridges; uses stage.rng after the clearing signs.
func build_horizon() -> void:
	pass

# Local, unsynchronised life (animals, villagers, wind).
func update_life(delta: float, focus: Vector3) -> void:
	if stage.life != null:
		stage.life.update(delta, focus)

# Extra shared-world providers (see world_sync.gd), e.g. snow.
func sync_providers(_game) -> Array:
	return []

# The stage loads a pre-baked scene (res://generated/...) instead of building.
func uses_baked_scene() -> bool:
	return false

func after_baked_load() -> void:
	pass

# ---------------------------------------------------------------- people

# Where a spectator camp at clearing `index` stands; Vector3.INF for none.
func spectator_camp(index: int, clearing: Vector3, s: float, outward: Vector3) -> Vector3:
	return clearing + outward * 6.0

# One-person groups along the roadside.
func roadside_spectators() -> bool:
	return true

# Stations of the marshals along the route.
func marshal_stations() -> Array:
	return [165.0, 365.0, 570.0, 730.0]
