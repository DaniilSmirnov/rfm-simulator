shader_type spatial;
render_mode unshaded, cull_back;
// A room behind window glass, drawn without geometry ("interior mapping"):
// the view ray enters the pane and is traced into a box room behind it (side
// walls, floor, ceiling, back wall) and past a few flat furniture cards that
// stand across the room. One quad per window, opaque, so a whole street of
// rooms costs one draw call. Built and merged by scripts/core/window_rooms.gd.
//
// Per vertex (window_rooms.gd pane()):
//   UV    position on the pane in metres from its centre (x right, y up)
//   UV2.x kind (integer part, KINDS in window_rooms.gd) + seed (fraction)
//   UV2.y 1000 * pane half width (cm) + drop to the floor below the centre (cm)
//   COLOR rgb: accent (curtains, goods on shop shelves); a: chance the room
//         is lit at night (1 = always lit, also a warm lamp by day)
//   NORMAL out of the building, TANGENT to the right as seen from outside.
// window_night (0 day .. 1 night) is set by sky_weather.gd.
global uniform float window_night;

const float HOME = 0.0;
const float SHOP = 1.0;
const float IZBA = 2.0;
const float CHALET = 3.0;
const float CAB = 4.0;
const float CHURCH = 5.0;
const float HALL = 6.0;
const float CAFE = 7.0;
const float OFFICE = 8.0;

varying vec4 info; // kind, seed, pane half width, drop to the floor
varying vec4 accent;

void vertex() {
	float kind = floor(UV2.x + 0.001);
	float packed = UV2.y;
	info = vec4(kind, UV2.x - kind, floor(packed / 1000.0 + 0.0001) / 100.0, mod(packed, 1000.0) / 100.0);
	accent = COLOR;
}

float hash(float n) {
	return fract(sin(n * 91.3458 + 47.123) * 43758.5453);
}

float box2(vec2 p, vec2 lo, vec2 hi) {
	return step(lo.x, p.x) * step(p.x, hi.x) * step(lo.y, p.y) * step(p.y, hi.y);
}

// Planks or tiles: a soft dark seam every `size` along a coordinate.
float seams(float v, float size, float width) {
	float f = fract(v / size);
	return 1.0 - 0.28 * (1.0 - smoothstep(0.0, width / size, min(f, 1.0 - f)));
}

vec3 pick(float s, vec3 a, vec3 b, vec3 c) {
	return s < 0.34 ? a : (s < 0.67 ? b : c);
}

// One furniture card standing across the room at depth z: returns colour in
// rgb and coverage in a. p is the hit point, y measured from the floor.
vec4 card(float kind, float layout, float seed, int index, vec2 p, float half_room, vec3 tint) {
	vec4 none = vec4(0.0);
	float x = p.x;
	float y = p.y;
	vec3 wood = vec3(0.42, 0.28, 0.18);
	if (kind == SHOP) {
		if (index == 0) {
			// Counter with a till, off to one side.
			float cx = (hash(seed * 5.0) - 0.5) * half_room;
			float top = box2(p, vec2(cx - 0.85, 0.0), vec2(cx + 0.85, 0.95));
			float till = box2(p, vec2(cx + 0.25, 0.95), vec2(cx + 0.6, 1.2));
			if (till > 0.5) return vec4(0.18, 0.19, 0.2, 1.0);
			if (top > 0.5) return vec4(mix(wood, tint, 0.15) * (y > 0.88 ? 1.25 : 1.0), 1.0);
		}
		return none;
	}
	if (kind == CAFE) {
		// Round tables with chairs, the bar at the back.
		float spacing = 1.6;
		float cx = mod(x + seed * 3.0 + float(index) * 0.8, spacing) - spacing * 0.5;
		float table = box2(vec2(cx, y), vec2(-0.4, 0.7), vec2(0.4, 0.76)) + box2(vec2(cx, y), vec2(-0.04, 0.0), vec2(0.04, 0.7));
		float chair = box2(vec2(abs(cx) - 0.55, y), vec2(-0.16, 0.42), vec2(0.16, 0.46)) + box2(vec2(abs(cx) - 0.68, y), vec2(-0.02, 0.0), vec2(0.02, 0.95));
		if (table > 0.5) return vec4(0.85, 0.83, 0.78, 1.0);
		if (chair > 0.5) return vec4(0.3, 0.22, 0.17, 1.0);
		return none;
	}
	if (kind == CAB) {
		// The operator's seat with its headrest, and a lever.
		float seat = box2(p, vec2(-0.28, 0.45), vec2(0.28, 1.15)) + box2(p, vec2(-0.16, 1.15), vec2(0.16, 1.38));
		float lever = box2(p, vec2(0.42, 0.3), vec2(0.46, 1.0));
		if (seat > 0.5) return vec4(0.12, 0.13, 0.14, 1.0);
		if (lever > 0.5) return vec4(0.08, 0.08, 0.08, 1.0);
		return none;
	}
	if (kind == HALL) {
		// Oak barrels on their sides, or concrete vats further in.
		if (index == 0) {
			float cx = mod(x + seed * 2.0, 1.05) - 0.525;
			vec2 q = vec2(cx, y - 0.45);
			float barrel = step(length(q / vec2(0.46, 0.44)), 1.0) + step(length(vec2(cx, y - 1.32) / vec2(0.46, 0.44)), 1.0) * step(0.5, hash(floor((x + seed * 2.0) / 1.05) + seed));
			if (barrel > 0.5) {
				float hoop = step(abs(abs(q.x) - 0.28), 0.03);
				return vec4(mix(vec3(0.43, 0.26, 0.15), vec3(0.16, 0.16, 0.16), hoop), 1.0);
			}
		} else {
			float cx = mod(x + seed * 5.0, 3.0) - 1.5;
			float vat = box2(vec2(cx, y), vec2(-1.1, 0.0), vec2(1.1, 4.0));
			if (vat > 0.5) return vec4(vec3(0.78, 0.76, 0.71) * (0.8 + 0.2 * cos(cx * 1.4)), 1.0);
		}
		return none;
	}
	if (kind == CHURCH) {
		// Candle stands: brass rods with flames.
		float cx = mod(x + seed * 2.0, 1.4) - 0.7;
		float stand = box2(vec2(cx, y), vec2(-0.03, 0.0), vec2(0.03, 1.0)) + box2(vec2(cx, y), vec2(-0.22, 0.98), vec2(0.22, 1.03));
		float flame = step(length(vec2(abs(cx) - 0.12, y - 1.1) / vec2(0.025, 0.05)), 1.0) + step(length(vec2(cx, y - 1.1) / vec2(0.025, 0.05)), 1.0);
		if (flame > 0.5) return vec4(1.6, 1.2, 0.5, 1.0);
		if (stand > 0.5) return vec4(0.62, 0.5, 0.24, 1.0);
		return none;
	}
	if (kind == OFFICE) {
		if (index == 0) {
			float cx = (hash(seed * 3.0) - 0.5) * half_room;
			float desk = box2(p, vec2(cx - 0.8, 0.0), vec2(cx + 0.8, 0.76));
			float screen = box2(p, vec2(cx - 0.25, 0.8), vec2(cx + 0.25, 1.15));
			float chair = box2(p, vec2(cx - 0.25, 0.76), vec2(cx + 0.25, 1.25));
			if (screen > 0.5) return vec4(0.15, 0.17, 0.2, 1.0);
			if (desk > 0.5) return vec4(wood * 1.2, 1.0);
			if (chair > 0.5) return vec4(0.12, 0.13, 0.15, 1.0);
		}
		return none;
	}
	if (kind == IZBA) {
		if (index == 0) {
			// Table under a cloth with a bench behind it.
			float cx = (layout < 0.5 ? 1.0 : -1.0) * half_room * 0.35;
			float top = box2(p, vec2(cx - 0.7, 0.68), vec2(cx + 0.7, 0.78));
			float cloth = box2(p, vec2(cx - 0.72, 0.5), vec2(cx + 0.72, 0.79));
			float legs = box2(vec2(abs(x - cx), y), vec2(0.55, 0.0), vec2(0.62, 0.7));
			float samovar = box2(p, vec2(cx - 0.12, 0.78), vec2(cx + 0.12, 1.1)) + box2(p, vec2(cx - 0.05, 1.1), vec2(cx + 0.05, 1.2));
			if (samovar > 0.5) return vec4(0.78, 0.55, 0.25, 1.0);
			if (cloth > 0.5) {
				float stripe = step(0.6, fract(x * 6.0));
				return vec4(mix(vec3(0.92, 0.9, 0.85), vec3(0.72, 0.16, 0.13), stripe * step(y, 0.6)), 1.0);
			}
			if (top + legs > 0.5) return vec4(wood, 1.0);
		} else {
			// The white Russian stove in the corner, its mouth and a ledge.
			float side = layout < 0.5 ? -1.0 : 1.0;
			float inner = side * (half_room - 1.4);
			float lo = min(inner, side * half_room);
			float hi = max(inner, side * half_room);
			float stove = box2(p, vec2(lo, 0.0), vec2(hi, 1.9));
			float mouth = box2(p, vec2((lo + hi) * 0.5 - 0.25, 0.75), vec2((lo + hi) * 0.5 + 0.25, 1.15));
			float pipe = box2(p, vec2((lo + hi) * 0.5 - 0.2, 1.9), vec2((lo + hi) * 0.5 + 0.2, 3.0));
			if (mouth > 0.5) return vec4(0.07, 0.05, 0.04, 1.0);
			if (stove + pipe > 0.5) return vec4(vec3(0.93, 0.92, 0.88) * seams(y, 0.5, 0.02), 1.0);
		}
		return none;
	}
	// HOME and CHALET: dining, sitting or sleeping.
	if (index == 0) {
		if (layout < 0.34) {
			float cx = (hash(seed * 11.0) - 0.5) * half_room * 0.5;
			float top = box2(p, vec2(cx - 0.8, 0.72), vec2(cx + 0.8, 0.78));
			float legs = box2(vec2(abs(x - cx), y), vec2(0.66, 0.0), vec2(0.72, 0.74));
			float jug = box2(p, vec2(cx - 0.1, 0.78), vec2(cx + 0.02, 0.98));
			float chair = box2(vec2(abs(x - cx), y), vec2(0.95, 0.0), vec2(1.0, 1.0)) + box2(vec2(abs(x - cx), y), vec2(0.95, 0.43), vec2(1.35, 0.48));
			if (jug > 0.5) return vec4(tint * 1.1 + 0.15, 1.0);
			if (top > 0.5) return vec4(mix(wood * 1.3, tint, 0.35), 1.0);
			if (legs + chair > 0.5) return vec4(wood * 0.75, 1.0);
		} else if (layout < 0.67) {
			// Sofa against the back of the room with cushions, a floor lamp.
			float cx = (hash(seed * 13.0) - 0.5) * half_room * 0.4;
			float base = box2(p, vec2(cx - 1.0, 0.1), vec2(cx + 1.0, 0.48));
			float back = box2(p, vec2(cx - 1.0, 0.48), vec2(cx + 1.0, 0.9));
			float arm = box2(vec2(abs(x - cx), y), vec2(0.85, 0.48), vec2(1.0, 0.65));
			float cushion = box2(vec2(abs(x - cx), y), vec2(0.3, 0.5), vec2(0.62, 0.78));
			float lamp = box2(p, vec2(cx + 1.25, 0.0), vec2(cx + 1.28, 1.45)) + box2(p, vec2(cx + 1.12, 1.4), vec2(cx + 1.42, 1.65));
			vec3 cloth = pick(hash(seed * 17.0), vec3(0.55, 0.38, 0.3), vec3(0.32, 0.42, 0.5), vec3(0.5, 0.52, 0.36));
			if (lamp > 0.5) return vec4(y > 1.4 ? vec3(0.95, 0.85, 0.6) : vec3(0.2), 1.0);
			if (cushion > 0.5) return vec4(tint * 0.9 + 0.1, 1.0);
			if (base + back + arm > 0.5) return vec4(cloth * (y > 0.48 ? 0.9 : 1.0), 1.0);
		} else {
			// Bed seen from its foot: blanket, pillows, the headboard.
			float cx = (hash(seed * 19.0) - 0.5) * half_room * 0.4;
			float blanket = box2(p, vec2(cx - 0.8, 0.25), vec2(cx + 0.8, 0.58));
			float pillow = box2(vec2(abs(x - cx), y), vec2(0.12, 0.58), vec2(0.62, 0.72));
			float head = box2(p, vec2(cx - 0.85, 0.58), vec2(cx + 0.85, 1.1));
			if (pillow > 0.5) return vec4(0.93, 0.93, 0.9, 1.0);
			if (blanket > 0.5) return vec4(mix(tint, vec3(0.9), 0.25) * (0.9 + 0.1 * step(0.5, fract(x * 3.0))), 1.0);
			if (head > 0.5) return vec4(wood, 1.0);
		}
	} else if (layout > 0.5) {
		// An armchair nearer the window, off to the side.
		float cx = (hash(seed * 23.0) > 0.5 ? 1.0 : -1.0) * half_room * 0.6;
		float chair = box2(p, vec2(cx - 0.42, 0.1), vec2(cx + 0.42, 0.45)) + box2(p, vec2(cx - 0.42, 0.45), vec2(cx + 0.42, 0.95));
		if (chair > 0.5) return vec4(vec3(0.46, 0.3, 0.22) * (y > 0.45 ? 0.85 : 1.0), 1.0);
	}
	return none;
}

// The back wall: what hangs on it or stands against it.
vec3 back_wall(float kind, float layout, float seed, vec2 p, float height, vec3 wall, vec3 tint) {
	float x = p.x;
	float y = p.y;
	if (kind == SHOP || kind == CAFE) {
		// Shelves to the ceiling, stocked with goods.
		float shelf = step(fract((y - 0.35) / 0.42), 0.08) * step(0.3, y) * step(y, 2.4);
		if (shelf > 0.5) return vec3(0.4, 0.28, 0.18);
		if (y > 0.35 && y < 2.4) {
			float cell = floor(x / 0.16);
			float row = floor((y - 0.35) / 0.42);
			float h = hash(cell * 7.0 + row * 13.0 + seed * 50.0);
			float item = step(0.18, h) * step(fract(x / 0.16), 0.8) * step(fract((y - 0.35) / 0.42), 0.2 + 0.7 * h);
			if (kind == CAFE) tint = mix(vec3(0.2, 0.4, 0.25), vec3(0.6, 0.2, 0.2), step(0.6, h));
			if (item > 0.5) return tint * (0.6 + 0.6 * h);
		}
		return wall;
	}
	if (kind == CHURCH) {
		// Gilded iconostasis: rows of icons in gold frames.
		float row = step(0.8, y) * step(y, height - 0.3);
		if (row > 0.5) {
			vec2 cell = vec2(fract(x / 0.7), fract((y - 0.8) / 1.0));
			float icon = box2(cell, vec2(0.15, 0.1), vec2(0.85, 0.85));
			float face = step(length((cell - vec2(0.5, 0.6)) / vec2(0.12, 0.14)), 1.0);
			if (face > 0.5 && icon > 0.5) return vec3(0.78, 0.6, 0.42);
			if (icon > 0.5) return mix(vec3(0.45, 0.16, 0.12), vec3(0.15, 0.25, 0.45), step(0.5, hash(floor(x / 0.7) + seed)));
			return vec3(0.85, 0.66, 0.25);
		}
		return wall;
	}
	if (kind == HALL) {
		return wall * (1.0 - 0.15 * step(fract(y / 1.5), 0.04));
	}
	if (kind == CAB) {
		return wall;
	}
	if (kind == IZBA) {
		// The red corner: an icon on a shelf with an embroidered towel.
		float cx = (layout < 0.5 ? -1.0 : 1.0) * 0.9;
		float icon = box2(p, vec2(cx - 0.18, height - 0.75), vec2(cx + 0.18, height - 0.3));
		float towel = box2(p, vec2(cx - 0.32, height - 0.95), vec2(cx + 0.32, height - 0.75)) + box2(vec2(abs(x - cx), y), vec2(0.24, height - 1.5), vec2(0.32, height - 0.75));
		if (icon > 0.5) return mix(vec3(0.8, 0.62, 0.25), vec3(0.4, 0.2, 0.12), box2(p, vec2(cx - 0.12, height - 0.68), vec2(cx + 0.12, height - 0.36)));
		if (towel > 0.5) return mix(vec3(0.95, 0.94, 0.9), vec3(0.75, 0.15, 0.12), step(0.7, fract(y * 8.0)));
		return wall;
	}
	if (kind == OFFICE) {
		float cabinet = box2(vec2(abs(x) , y), vec2(0.9, 0.0), vec2(1.5, 1.9));
		if (cabinet > 0.5) return vec3(0.55, 0.5, 0.42) * (step(0.04, fract(y / 0.48)));
		float portrait = box2(p, vec2(-0.3, 1.45), vec2(0.3, 2.2));
		if (portrait > 0.5) return mix(vec3(0.65, 0.5, 0.25), vec3(0.3, 0.32, 0.38), box2(p, vec2(-0.24, 1.52), vec2(0.24, 2.12)));
		return wall;
	}
	// HOME, CHALET: a dresser, a bookcase or a picture, chosen per room.
	float pick_back = hash(seed * 29.0);
	if (pick_back < 0.35) {
		float cx = (hash(seed * 31.0) - 0.5) * 1.2;
		float dresser = box2(p, vec2(cx - 0.7, 0.0), vec2(cx + 0.7, 0.9));
		float plates = step(length(vec2(fract((x - cx) / 0.35) - 0.5, (y - 1.35) / 0.35) / 0.32), 1.0) * box2(p, vec2(cx - 0.7, 1.15), vec2(cx + 0.7, 1.55));
		float rack = box2(p, vec2(cx - 0.75, 1.1), vec2(cx + 0.75, 1.62));
		if (plates > 0.5) return vec3(0.9, 0.9, 0.86) * (0.85 + 0.15 * hash(floor((x - cx) / 0.35)));
		if (rack > 0.5 || dresser > 0.5) return vec3(0.4, 0.27, 0.17) * (dresser > 0.5 ? seams(y, 0.3, 0.015) : 0.85);
	} else if (pick_back < 0.7) {
		float cx = (hash(seed * 37.0) - 0.5) * 1.0;
		float case_ = box2(p, vec2(cx - 0.6, 0.0), vec2(cx + 0.6, 2.1));
		if (case_ > 0.5) {
			float shelf = step(fract(y / 0.42), 0.07);
			float book = hash(floor(x / 0.07) * 3.0 + floor(y / 0.42) * 17.0);
			vec3 spine = pick(book, vec3(0.55, 0.15, 0.12), vec3(0.15, 0.3, 0.45), vec3(0.75, 0.62, 0.35));
			float top = step(fract(y / 0.42), 0.3 + 0.55 * book);
			return shelf > 0.5 || abs(x - cx) > 0.55 ? vec3(0.38, 0.25, 0.16) : (top > 0.5 ? spine : vec3(0.1, 0.08, 0.06));
		}
	} else {
		float cx = (hash(seed * 41.0) - 0.5) * 1.0;
		float frame = box2(p, vec2(cx - 0.45, 1.25), vec2(cx + 0.45, 1.9));
		if (frame > 0.5) {
			float inside = box2(p, vec2(cx - 0.38, 1.32), vec2(cx + 0.38, 1.83));
			vec3 sky = mix(vec3(0.55, 0.7, 0.8), vec3(0.75, 0.62, 0.35), step(y, 1.5));
			return inside > 0.5 ? sky : vec3(0.65, 0.48, 0.22);
		}
	}
	return wall;
}

void fragment() {
	// The varyings are the same at every corner, but interpolation adds a
	// little noise that the hashes would blow up: snap them back.
	float kind = floor(info.x + 0.5);
	float seed = floor(info.y * 997.0 + 0.5) / 997.0;
	float pane_half = max(floor(info.z * 100.0 + 0.5) / 100.0, 0.2);
	float drop = floor(info.w * 100.0 + 0.5) / 100.0;
	vec3 tint = accent.rgb;
	// Into the room: x right, y up, z away from the glass.
	vec3 ray = -VIEW;
	vec3 d = normalize(vec3(dot(ray, TANGENT), dot(ray, BINORMAL), -dot(ray, NORMAL)));
	vec2 at = UV;
	float layout = hash(seed * 7.0 + 1.0);
	float height = kind == CHURCH ? 5.5 : (kind == HALL ? 4.6 : (kind == CAB ? 1.9 : (kind == IZBA ? 2.4 : 2.8)));
	float depth = kind == CAB ? 1.3 : (kind == HALL ? 9.0 : (kind == CHURCH ? 8.0 : 3.2 + 1.6 * hash(seed * 3.0)));
	float half_room = kind == CAB ? pane_half + 0.15 : max(pane_half + 0.6, 1.3 + 0.7 * hash(seed * 5.0));
	float shift = (hash(seed * 9.0) - 0.5) * (half_room - pane_half) * 0.8;
	float lo_x = -half_room + shift;
	float hi_x = half_room + shift;
	float floor_y = -drop;
	float ceil_y = floor_y + height;
	// Trace the room box from the glass.
	float tx = ((d.x > 0.0 ? hi_x : lo_x) - at.x) / (abs(d.x) > 1e-4 ? d.x : 1e-4);
	float ty = ((d.y > 0.0 ? ceil_y : floor_y) - at.y) / (abs(d.y) > 1e-4 ? d.y : 1e-4);
	float tz = depth / max(d.z, 1e-4);
	float t = min(min(tx, ty), tz);
	vec3 hit = vec3(at, 0.0) + d * t;
	// Walls, floor and ceiling by kind.
	vec3 wall = pick(hash(seed * 43.0), vec3(0.93, 0.88, 0.76), vec3(0.8, 0.85, 0.82), vec3(0.9, 0.8, 0.66));
	vec3 floor_c = pick(hash(seed * 47.0), vec3(0.62, 0.36, 0.25), vec3(0.5, 0.36, 0.24), vec3(0.72, 0.6, 0.45));
	vec3 ceil_c = vec3(0.92, 0.9, 0.85);
	if (kind == IZBA) {
		wall = vec3(0.6, 0.45, 0.3);
		floor_c = vec3(0.55, 0.42, 0.28);
		ceil_c = vec3(0.58, 0.45, 0.3);
	} else if (kind == CHALET) {
		wall = vec3(0.7, 0.5, 0.32);
		floor_c = vec3(0.5, 0.34, 0.22);
		ceil_c = vec3(0.62, 0.44, 0.28);
	} else if (kind == CAB) {
		wall = vec3(0.46, 0.48, 0.48);
		floor_c = vec3(0.12, 0.12, 0.13);
		ceil_c = vec3(0.52, 0.53, 0.52);
	} else if (kind == CHURCH) {
		wall = vec3(0.86, 0.82, 0.72);
		floor_c = vec3(0.45, 0.33, 0.22);
	} else if (kind == HALL) {
		wall = vec3(0.8, 0.76, 0.66);
		floor_c = vec3(0.55, 0.53, 0.5);
		ceil_c = vec3(0.4, 0.3, 0.22);
	} else if (kind == SHOP || kind == CAFE || kind == OFFICE) {
		wall = mix(wall, vec3(0.95), 0.4);
		floor_c = mix(vec3(0.82, 0.8, 0.74), vec3(0.3, 0.3, 0.32), step(0.5, mod(floor(hit.x / 0.4) + floor(hit.z / 0.4), 2.0)));
	}
	vec3 color;
	if (t == tz) {
		color = back_wall(kind, layout, seed, vec2(hit.x, hit.y - floor_y), height, wall, tint);
		if (kind == IZBA) color *= seams(hit.y, 0.24, 0.03);
	} else if (t == ty) {
		if (d.y < 0.0) {
			color = floor_c * (kind == SHOP || kind == CAFE || kind == OFFICE ? 1.0 : seams(kind == HOME ? hit.x + 7.0 * floor(hit.z / 0.35) : hit.x, kind == HOME ? 0.35 : 0.18, 0.012) * seams(hit.z, kind == HOME ? 0.35 : 1.6, 0.012));
			// A rug in the middle of a home.
			if ((kind == HOME || kind == CHALET) && box2(vec2(hit.x - shift, hit.z), vec2(-1.0, depth * 0.3), vec2(1.0, depth * 0.75)) > 0.5)
				color = mix(tint, vec3(0.75, 0.6, 0.4), 0.5) * (0.85 + 0.15 * step(0.5, fract(hit.x * 2.0)));
		} else {
			color = ceil_c;
			if (kind == HOME || kind == IZBA || kind == HALL) color *= mix(1.0, 0.55, step(fract(hit.z / 0.8), 0.18));
		}
	} else {
		color = wall * 0.88;
		if (kind == IZBA) color *= seams(hit.y, 0.24, 0.03);
		if (kind == CHALET) color *= seams(hit.z, 0.16, 0.01);
	}
	// Furniture cards in front of what the ray hit, nearest first.
	float card_z[2] = float[2](depth * 0.42, depth * 0.72);
	if (kind == CAB) { card_z[0] = 0.55; card_z[1] = 0.9; }
	if (kind == HALL) { card_z[0] = 2.0; card_z[1] = 5.5; }
	if (kind == SHOP || kind == OFFICE) { card_z[0] = depth * 0.45; card_z[1] = depth * 0.45; }
	if (kind == HOME || kind == CHALET) { card_z[0] = depth * 0.38; card_z[1] = depth * 0.72; }
	float hit_depth = hit.z;
	for (int i = 0; i < 2; i++) {
		int index = (kind == HOME || kind == CHALET) ? 1 - i : i;
		float cz = card_z[i];
		float tc = cz / max(d.z, 1e-4);
		if (tc < t) {
			vec3 q = vec3(at, 0.0) + d * tc;
			if (q.x > lo_x && q.x < hi_x) {
				vec4 c = card(kind, layout, seed, index, vec2(q.x - shift * 0.5, q.y - floor_y), half_room, tint);
				if (c.a > 0.5) {
					color = c.rgb;
					hit_depth = cz;
					break;
				}
			}
		}
	}
	// Light: daylight from the window falling off into the room; at night a
	// lamp in lit rooms, a faint glow in the rest.
	float lit = step(hash(seed * 53.0 + 0.5), floor(accent.a * 20.0 + 0.5) / 20.0);
	float day = 1.0 * mix(1.0, 0.62, clamp(hit_depth / max(depth, 1.0), 0.0, 1.0));
	if (t == ty && d.y < 0.0) day += 0.18 * (1.0 - smoothstep(0.0, 1.8, hit.z));
	vec3 lamp = vec3(1.0, 0.9, 0.72) * (0.95 - 0.25 * clamp(length(vec2(hit.x - shift, hit.z - depth * 0.5)) / (half_room + depth * 0.5), 0.0, 1.0));
	vec3 day_light = vec3(day) * (lit > 0.5 && accent.a > 0.95 ? vec3(1.08, 1.0, 0.86) : vec3(1.0));
	vec3 night_light = lit > 0.5 ? lamp : vec3(0.3, 0.33, 0.45);
	vec3 room = color * mix(day_light, night_light, window_night);
	// Curtains drawn back to both sides of the pane, net curtains in an izba.
	float edge = abs(at.x) / pane_half;
	if ((kind == HOME || kind == CHALET || kind == OFFICE) && hash(seed * 59.0) < 0.75 && edge > 0.7) {
		vec3 cloth = mix(tint, vec3(0.92, 0.9, 0.85), 0.35) * (0.85 + 0.15 * sin(at.x * 60.0));
		room = cloth * mix(vec3(0.75), lit > 0.5 ? vec3(0.95, 0.82, 0.62) : vec3(0.18, 0.2, 0.26), window_night);
	}
	if (kind == IZBA && at.y < 0.0) {
		// Sheer white cotton with a woven border along its top.
		float border = step(-0.12, at.y) * step(fract(at.x * 12.0), 0.5);
		room = mix(room, vec3(0.95, 0.95, 0.92) * mix(0.82, lit > 0.5 ? 0.85 : 0.2, window_night), 0.55 + 0.3 * border);
	}
	// The glass: a sky reflection that grows at grazing angles.
	float fresnel = 0.05 + 0.45 * pow(1.0 - clamp(d.z, 0.0, 1.0), 5.0);
	vec3 sky = mix(vec3(0.66, 0.74, 0.8), vec3(0.04, 0.05, 0.08), window_night) * (0.9 + 0.1 * at.y / max(pane_half, 0.3));
	vec3 srgb = mix(room, sky, fresnel);
	ALBEDO = pow(max(srgb, vec3(0.0)), vec3(2.2));
}
