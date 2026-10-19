extends RefCounted
# Who the people are: the four spectator looks shared by players, peers,
# camp spectators, officials, villagers and the medic, and the outfits they
# change into. The body generator (tools/assets/character_source.gd) bakes one
# GLB per look and outfit from these records; props.gd loads them and dresses
# first-person hands to match.

const SPECTATOR_MODELS = [
	{"name": "Шашлычник", "skin": "d9a482", "shirt": "202b31", "trim": "92985a", "pants": "394650", "hair": "71451f", "hat": "", "sleeves": false, "long_pants": false, "beard": false},
	{"name": "Болельщик", "skin": "c8906a", "shirt": "346a9c", "trim": "e2e4cc", "pants": "374f69", "hair": "332a25", "hat": "cap", "sleeves": true, "long_pants": true, "beard": false},
	{"name": "Бородатый механик", "skin": "e0b393", "shirt": "bb602d", "trim": "e9c678", "pants": "343a39", "hair": "a65d29", "hat": "", "sleeves": false, "long_pants": false, "beard": true},
	{"name": "Лесной турист", "skin": "c6a08b", "shirt": "65736d", "trim": "d9b95d", "pants": "45513b", "hair": "473329", "hat": "beanie", "sleeves": true, "long_pants": true, "beard": false},
]

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
