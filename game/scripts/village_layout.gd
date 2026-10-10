extends RefCounted
# Authoring data for the «Виноградники» stage: a Provençal hill village between
# a lavender plateau and terraced vineyards (docs/PROVENCE_VILLAGE_STAGE.md).
# Places are given in route coordinates — station s (metres from the start),
# lateral offset (positive = right of the direction of travel) and an optional
# shift along the road — so this file reads like the approved route map.

# Plan view (x, z) of the route spline. Stations are arc length in metres.
const CONTROL_POINTS = [
	Vector2(0, 0), Vector2(4, -45), Vector2(20, -90), Vector2(36, -130), Vector2(40, -175),
	Vector2(34, -215), Vector2(28, -250),
	Vector2(20, -282), Vector2(6, -306), Vector2(-4, -330), Vector2(-6, -356),
	Vector2(-10, -380), Vector2(-24, -390), Vector2(-46, -392),
	Vector2(-64, -400), Vector2(-72, -420), Vector2(-70, -446), Vector2(-60, -468),
	Vector2(-44, -486), Vector2(-38, -508), Vector2(-48, -526),
	Vector2(-74, -538), Vector2(-96, -552), Vector2(-98, -572), Vector2(-78, -584),
	Vector2(-40, -592), Vector2(0, -604), Vector2(34, -624), Vector2(56, -656), Vector2(64, -700), Vector2(60, -740),
]

# Road character per section. Width and pace blend over BLEND metres at joints.
const BLEND = 8.0
const SECTIONS = [
	{"id": "plateau", "from": 0.0, "to": 250.0, "surface": "asphalt", "width": 7.0, "speed": 27.0},
	{"id": "avenue", "from": 250.0, "to": 290.0, "surface": "asphalt", "width": 6.6, "speed": 23.0},
	{"id": "grand_rue", "from": 290.0, "to": 382.0, "surface": "cobble", "width": 6.0, "speed": 15.0},
	{"id": "square", "from": 382.0, "to": 446.0, "surface": "cobble", "width": 6.4, "speed": 11.0},
	{"id": "lane", "from": 446.0, "to": 528.0, "surface": "cobble", "width": 5.8, "speed": 13.0},
	{"id": "terraces", "from": 528.0, "to": 700.0, "surface": "gravel", "width": 6.2, "speed": 17.0},
	{"id": "valley", "from": 700.0, "to": 841.0, "surface": "gravel", "width": 6.8, "speed": 26.0},
]
# The slow hairpin between the vineyard terraces.
const HAIRPIN = Vector2(640.0, 692.0)
const HAIRPIN_SPEED = 11.0

# The built-up village: stone houses, pavements and lamps.
const VILLAGE = Vector2(290.0, 528.0)
const PAVEMENT = 1.5
const KERB = 0.14
# Street junctions keep the kerb open for side alleys.
const ALLEYS = [326.0, 352.0, 470.0, 500.0]

# Spectator spots: [station, side, lateral]. The second one is on the square.
# The second spot is "square": a point in square coordinates (SQUARE_CLEARING).
const CLEARINGS = [[135.0, 1.0, 16.0], "square", [662.0, 1.0, 22.0], [792.0, -1.0, 15.0]]
const SQUARE_CLEARING = Vector2(6.0, -3.0)

# Terrain flattened under yards and squares: [station, lateral, along, width, depth, margin].
const SQUARE = {"s": 372.0, "lateral": -19.0, "along": 8.0, "size": Vector2(24.0, 24.0)}
const FLATS = [
	[135.0, 24.0, 0.0, 34.0, 26.0, 10.0], # mas and lavender distillery
	[662.0, 22.0, 0.0, 24.0, 20.0, 13.0], # spectators over the hairpin
	[628.0, -24.0, 0.0, 26.0, 22.0, 15.0], # wine domaine
	[808.0, 16.0, 0.0, 30.0, 22.0, 14.0], # cooperative winery at the finish
	[792.0, -15.0, 0.0, 18.0, 16.0, 7.0], # finish-side spectators
]

# Terraced house rows: [from, to, side]. Fronts stand on the pavement edge.
const HOUSE_ROWS = [
	[292.0, 381.0, 1.0], [294.0, 356.0, -1.0],
	[388.0, 446.0, 1.0], [450.0, 527.0, 1.0], [452.0, 525.0, -1.0],
]
# Breaks in the rows for landmarks: [from, to, side].
const ROW_GAPS = [[415.0, 436.0, 1.0], [480.0, 496.0, -1.0]]
# A second row of houses stands behind each street front, across a back lane:
# its facades are this far beyond the backs of the street houses' annexes.
const BACK_LANE = 3.5
# A dry-stone hut (borie) inside the hairpin, among olives and cypresses.
const BORIE = {"s": 668.0, "lateral": 30.0}
# The church faces the square across the road; its tower is reached on foot.
const CHURCH = {"s": 425.0, "lateral": 20.0}
const ROOF_TERRACE_HOUSE = {"s": 336.0, "side": 1.0}
const MAIRIE = {"s": 372.0, "lateral": -36.0}
const CAFE = {"s": 362.0, "lateral": -9.5}
const LAVOIR = {"s": 488.0, "lateral": -8.5}
const CEMETERY = {"s": 470.0, "lateral": -38.0, "size": Vector2(18.0, 22.0)}
const GATES = [[288.0, 1.0], [530.0, -1.0]]
const DISTILLERY = {"s": 135.0, "lateral": 34.0}
const DOMAINE = {"s": 628.0, "lateral": -26.0}
const COOPERATIVE = {"s": 812.0, "lateral": 18.0}
const PLANE_AVENUE = Vector2(244.0, 290.0)
const LAMPS = [302.0, 318.0, 344.0, 378.0, 412.0, 438.0, 462.0, 494.0, 524.0]

# Crops. Lavender fills the plateau, vines the slopes and the valley.
const LAVENDER = Vector2(10.0, 246.0)
const VINES = Vector2(536.0, 836.0)
