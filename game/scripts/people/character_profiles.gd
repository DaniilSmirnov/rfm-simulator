extends RefCounted
# Who the people are: the spectator looks shared by players, peers,
# camp spectators, officials, villagers and the medic, and the outfits they
# change into. The body generator (tools/assets/character_source.gd) bakes one
# GLB per look and outfit from these records; props.gd loads them and dresses
# first-person hands to match.

const SPECTATOR_MODELS = [
	{"name": "Шашлычник", "skin": "d9a482", "shirt": "202b31", "trim": "92985a", "pants": "394650", "hair": "71451f", "hat": "", "sleeves": false, "long_pants": false, "beard": false},
	{"name": "Болельщик", "skin": "c8906a", "shirt": "346a9c", "trim": "e2e4cc", "pants": "374f69", "hair": "332a25", "hat": "cap", "sleeves": true, "long_pants": true, "beard": false},
	{"name": "Бородатый механик", "skin": "e0b393", "shirt": "bb602d", "trim": "e9c678", "pants": "343a39", "hair": "a65d29", "hat": "", "sleeves": false, "long_pants": false, "beard": true},
	{"name": "Лесной турист", "skin": "c6a08b", "shirt": "65736d", "trim": "d9b95d", "pants": "45513b", "hair": "473329", "hat": "beanie", "sleeves": true, "long_pants": true, "beard": false},
	{"name": "Фотограф", "skin": "e8c0a0", "shirt": "5b6770", "trim": "d8d2c0", "pants": "4b4a42", "hair": "2b2522", "hat": "", "sleeves": true, "long_pants": true, "beard": false, "glasses": "clear"},
	{"name": "Дед-болельщик", "skin": "d7a98c", "shirt": "7a8f6a", "trim": "efe3c4", "pants": "5a5246", "hair": "c9c6bf", "hat": "", "sleeves": false, "long_pants": true, "beard": false, "mustache": true, "hair_style": "bald"},
	{"name": "Студент", "skin": "b9825f", "shirt": "2f7d6d", "trim": "f2d35b", "pants": "3a4458", "hair": "1e1a18", "hat": "cap", "hat_color": "f2d35b", "sleeves": false, "long_pants": false, "beard": false},
	{"name": "Фанат в очках", "skin": "cf9a78", "shirt": "c8202e", "trim": "f4f4f0", "pants": "2b2f36", "hair": "5a3b22", "hat": "", "sleeves": false, "long_pants": true, "beard": false, "glasses": "shades"},
	{"name": "Дачник", "skin": "d8a27e", "shirt": "e2d9b8", "trim": "6f8f5a", "pants": "6b5a3e", "hair": "6f6a62", "hat": "panama", "hat_color": "e9e1c8", "sleeves": false, "long_pants": false, "beard": true},
	{"name": "Болельщица", "skin": "edc3a6", "shirt": "e05a8a", "trim": "fbe9a0", "pants": "334a6e", "hair": "8a4a22", "hat": "", "sleeves": false, "long_pants": true, "beard": false, "female": true, "hair_style": "ponytail"},
	{"name": "Туристка", "skin": "c99376", "shirt": "3f8fb5", "trim": "f3efe2", "pants": "4b5a3a", "hair": "2a1e1a", "hat": "", "sleeves": true, "long_pants": false, "beard": false, "female": true, "hair_style": "long"},
	{"name": "Коллекционер нашивок", "skin": "d29a78", "shirt": "d9d2c3", "trim": "4d6b3c", "pants": "3d4a5a", "hair": "5b4a3e", "hat": "", "sleeves": false, "long_pants": true, "beard": false, "mustache": true, "build": "big", "patch_vest": true, "vest": "4d6b3c", "playable": false},
]

# Optional look keys: "hair_style" ("short" default, "bald", "ponytail",
# "long"), "glasses" ("clear", "shades"), "mustache", "female" (slimmer
# torso, lashes, lips), "hat_color" for a summer "cap" or "panama", "build":
# "big" (taller and broader), "patch_vest" (a vest of rally patches in colour
# "vest", worn over every outfit), "playable": false (a spectator only, not
# offered in the menu).

# Outfits: clothes a stage dresses everyone in (stage_biome.gd outfit()); ""
# keeps the summer clothes above. An outfit record per look replaces only the
# clothes: face, hair, beard and name stay, so every person is recognisable.
#   winter: puffer jacket ("shirt") with quilted seams, scarf, mittens
#           ("gloves"), insulated trousers, fur-trimmed snow boots and a warm
#           hat: "bobble" (knitted, pompom), "ushanka" (fur, ear flaps),
#           "beanie" (the tourist's own, with a pompom and the hood).
const OUTFITS = {
	"winter": [
		{"shirt": "b8352e", "trim": "eee6d2", "scarf": "e2c25a", "gloves": "2b3034", "pants": "2f383f", "hat": "bobble", "hat_color": "2c4466", "hat_trim": "eee6d2"},
		{"shirt": "2f62a3", "trim": "e9ecef", "scarf": "c73a30", "gloves": "c73a30", "pants": "2c3a4c", "hat": "bobble", "hat_color": "c73a30", "hat_trim": "f2f0e8"},
		{"shirt": "d47a2a", "trim": "f0d27c", "scarf": "5c6f5b", "gloves": "4a3a2e", "pants": "33393a", "hat": "ushanka", "hat_color": "6b5443", "hat_trim": "8d735f"},
		{"shirt": "4e6a4c", "trim": "dcbd61", "scarf": "a8432f", "gloves": "3b4038", "pants": "3e4636", "hat": "beanie", "hat_color": "a8432f", "hat_trim": "e7dccb"},
		{"shirt": "3d4a55", "trim": "e2b23a", "scarf": "e2b23a", "gloves": "26292c", "pants": "2f3236", "hat": "bobble", "hat_color": "3a3f45", "hat_trim": "e2b23a"},
		{"shirt": "5d6b44", "trim": "e6dcc4", "scarf": "8e2f2a", "gloves": "4a3a2e", "pants": "3b3732", "hat": "ushanka", "hat_color": "4a3c30", "hat_trim": "7b6857"},
		{"shirt": "f0c43a", "trim": "2c3a4c", "scarf": "2f7d6d", "gloves": "2f7d6d", "pants": "2c3a4c", "hat": "bobble", "hat_color": "2f7d6d", "hat_trim": "f2f0e8"},
		{"shirt": "c8202e", "trim": "f4f4f0", "scarf": "f4f4f0", "gloves": "202326", "pants": "23272c", "hat": "bobble", "hat_color": "202326", "hat_trim": "c8202e"},
		{"shirt": "6e4a33", "trim": "e6d8b4", "scarf": "c99a3c", "gloves": "3a2d24", "pants": "3d3a33", "hat": "ushanka", "hat_color": "5b4a3c", "hat_trim": "a08a73"},
		{"shirt": "e9ecef", "trim": "e05a8a", "scarf": "e05a8a", "gloves": "e05a8a", "pants": "2f3e5a", "hat": "bobble", "hat_color": "e05a8a", "hat_trim": "f7f3ee"},
		{"shirt": "7a3f8f", "trim": "f3efe2", "scarf": "e7b43c", "gloves": "3a2f45", "pants": "34383e", "hat": "bobble", "hat_color": "3f8fb5", "hat_trim": "f3efe2"},
		{"shirt": "2c3540", "trim": "d9d2c3", "scarf": "c8202e", "gloves": "26292c", "pants": "2f3640", "hat": "bobble", "hat_color": "c8202e", "hat_trim": "f4f1e8"},
	],
}

static func profile(variant: int, outfit: String = "") -> Dictionary:
	var look: Dictionary = SPECTATOR_MODELS[posmod(variant, SPECTATOR_MODELS.size())]
	if not OUTFITS.has(outfit):
		return look
	var dressed = look.duplicate()
	dressed.merge(OUTFITS[outfit][posmod(variant, OUTFITS[outfit].size())], true)
	dressed.merge({"outfit": outfit, "sleeves": true, "long_pants": true}, true)
	return dressed

# Colours of a first-person forearm: [sleeve, hand].
static func forearm_colors(look: Dictionary) -> Array:
	var skin = Color(look.skin)
	var sleeve = Color(look.shirt) if look.hat == "beanie" or look.has("outfit") else skin
	return [sleeve, Color(look.get("gloves", look.skin))]

# The baked body of a look in an outfit (tools/assets/export_characters.gd).
static func model_path(variant: int, outfit: String = "") -> String:
	var index = posmod(variant, SPECTATOR_MODELS.size())
	return "res://models/characters/spectator_%d.glb" % index if not OUTFITS.has(outfit) else "res://models/characters/spectator_%s_%d.glb" % [outfit, index]

# Looks a player can pick, in menu order: the index of a look is its
# "character" content_id in store_catalog.json and in room membership. The
# stage still chooses the clothes, so a pick is worn in summer or winter dress.
static func playable() -> Array[int]:
	var looks: Array[int] = []
	for variant in range(SPECTATOR_MODELS.size()):
		if SPECTATOR_MODELS[variant].get("playable", true):
			looks.append(variant)
	return looks

# The menu card image of a look in an outfit (tools/screenshots/export_menu_previews.gd).
static func preview_path(variant: int, outfit: String = "") -> String:
	var index = posmod(variant, SPECTATOR_MODELS.size())
	return "res://textures/previews/character_%d.webp" % index if not OUTFITS.has(outfit) else "res://textures/previews/character_%s_%d.webp" % [outfit, index]

# Every look's body in an outfit, by path.
static func load_models(outfit: String) -> Dictionary:
	var scenes = {}
	for variant in range(SPECTATOR_MODELS.size()):
		scenes[model_path(variant, outfit)] = load(model_path(variant, outfit))
	return scenes
