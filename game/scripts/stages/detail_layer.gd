extends RefCounted
# How one instanced decoration layer (grass, berries, vines, tree crowns) is
# drawn: a typed description passed to stage.detail_batch() instead of option
# strings, so a misspelt option fails at parse time instead of silently
# breaking harvesting or culling.
#
#   DetailLayer.tiled(110.0).harvestable()

# Split into 64 m culling tiles named <name>_Tile_x_y ("GrassTile" for ForestGrass).
var tiles := false
# Visibility range of tiles, metres.
var range_end := 160.0
# Instances can be hidden one by one when collected (berries, mushrooms, figs).
var collectible := false
# Shared id of a fallable tree group (village groves): every layer of one tree
# hides together when it is felled.
var tree_group := ""
# Trunk layer of a tree group: these bases and heights join stage.trees[] and
# collide with cars.
var tree_bases: Array = []
var tree_heights: Array = []
var texture: Texture2D

static func plain():
	return new()

static func tiled(range_metres: float = 160.0):
	var layer = new()
	layer.tiles = true
	layer.range_end = range_metres
	return layer

func harvestable():
	collectible = true
	return self

func textured(albedo: Texture2D):
	texture = albedo
	return self

func tree(group: String, bases: Array = [], heights: Array = []):
	tree_group = group
	tree_bases = bases
	tree_heights = heights
	return self
