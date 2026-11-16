shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

// A falling raindrop or snowflake (scripts/core/sky_weather.gd), hidden where
// it would be under a roof (scripts/core/rain_shelter.gd): below the height
// map of crowns, roofs and solids, or inside a car next to the camera.
// Billboards like StandardMaterial3D with billboard_keep_scale: rain streaks
// stay upright (upright = true), flakes face the camera.
uniform vec4 color : source_color = vec4(1.0);
uniform sampler2D flake : source_color, hint_default_white, filter_linear;
uniform bool upright = true;
// Height of the roof over each cell; roof_area = (x, z of the map's corner, 1 / size).
uniform sampler2D roof : filter_nearest, repeat_disable;
uniform vec3 roof_area = vec3(0.0, 0.0, 0.0);
uniform mat4 car_inverse[4];
uniform vec4 car_box[4];

varying vec3 world;

void vertex() {
	if (upright) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(normalize(cross(vec3(0.0, 1.0, 0.0), INV_VIEW_MATRIX[2].xyz)), 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(normalize(cross(INV_VIEW_MATRIX[0].xyz, vec3(0.0, 1.0, 0.0))), 0.0), MODEL_MATRIX[3]);
	} else {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	}
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	world = (INV_VIEW_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = (world.xz - roof_area.xy) * roof_area.z;
	if (roof_area.z > 0.0 && cell.x >= 0.0 && cell.y >= 0.0 && cell.x < 1.0 && cell.y < 1.0 && world.y < texture(roof, cell).r) {
		discard;
	}
	for (int i = 0; i < 4; i++) {
		if (car_box[i].w > 0.5) {
			vec3 local = (car_inverse[i] * vec4(world, 1.0)).xyz;
			if (abs(local.x) < car_box[i].x && abs(local.z) < car_box[i].z && local.y < car_box[i].y) {
				discard;
			}
		}
	}
	vec4 tint = color * texture(flake, UV);
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
