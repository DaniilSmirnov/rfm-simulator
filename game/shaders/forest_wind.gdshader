shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_disabled;
#include "res://shaders/lake_waves.gdshaderinc"

// One animated material for the living forest: tree crowns, grass, shrubs and reeds
// lean with a shared, slowly travelling gust; lily pads ride the lake surface.
uniform float sway_amount = 0.25;     // fraction of the instance's own height moved at the free end
uniform float base_y = 0.0;           // mesh-local height where bending starts
uniform float span_y = 1.0;           // mesh-local distance over which the bend grows
uniform float wind_speed = 1.0;
uniform vec2 wind_dir = vec2(0.82, 0.57);
uniform bool tree_layers = false;     // INSTANCE_CUSTOM.x holds the layer centre as a fraction of tree height
uniform bool floating = false;        // follow lake_wave() instead of the wind

float srgb_channel(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 disp = vec3(0.0);
	if (floating) {
		disp.y = lake_wave(origin.xz, TIME);
	} else {
		float scale_y = length(MODEL_MATRIX[1].xyz);
		float phase = dot(origin.xz, vec2(0.37, 0.53));
		float gust = 0.5 + 0.5 * sin(TIME * 0.7 * wind_speed + origin.x * 0.035 + origin.z * 0.027);
		float flutter = 0.6 * sin(TIME * 2.3 * wind_speed + phase * 3.1) + 0.3 * sin(TIME * 4.1 * wind_speed + phase * 1.7);
		float push = (0.25 + 0.75 * gust) + flutter * 0.35 * (0.3 + gust);
		float k;
		float height = scale_y;
		if (tree_layers) {
			float standing = step(0.92, MODEL_MATRIX[1].y / max(scale_y, 0.0001));
			float fraction = INSTANCE_CUSTOM.x;
			height = scale_y / mix(0.49, 0.64, step(fraction, 0.4));
			k = fraction * fraction * standing;
		} else {
			k = clamp((VERTEX.y - base_y) / max(span_y, 0.0001), 0.0, 1.0);
			k *= k;
		}
		disp.xz = wind_dir * push * sway_amount * height * k;
	}
	VERTEX += inverse(mat3(MODEL_MATRIX)) * disp;
}

void fragment() {
	ALBEDO = vec3(srgb_channel(COLOR.r), srgb_channel(COLOR.g), srgb_channel(COLOR.b));
	ROUGHNESS = 0.95;
}
