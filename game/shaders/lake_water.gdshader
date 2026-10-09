shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;
#include "res://shaders/lake_waves.gdshaderinc"

// Vertex colour: rgb is the water tint chosen from the lake-bed depth,
// alpha is opacity (transparent on the shoreline, dark and opaque in the deep).
uniform vec3 sky_tint : source_color = vec3(0.62, 0.78, 0.9);
uniform float foam_width = 0.22;

varying vec3 world_position;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_position = world;
	float t = TIME;
	VERTEX.y += lake_wave(world.xz, t);
	vec2 g = lake_wave_gradient(world.xz, t);
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
}

float srgb_channel(float c) {
	return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}

void fragment() {
	vec3 tint = vec3(srgb_channel(COLOR.r), srgb_channel(COLOR.g), srgb_channel(COLOR.b));
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	float shore = 1.0 - smoothstep(0.02, foam_width, COLOR.a);
	float ripple = 0.5 + 0.5 * sin(TIME * 0.9 + world_position.x * 0.8 + world_position.z * 0.6);
	vec3 foam = vec3(0.9, 0.95, 0.95) * shore * (0.25 + 0.35 * ripple);
	ALBEDO = mix(tint, sky_tint, fresnel * 0.55) + foam;
	ALPHA = clamp(COLOR.a + fresnel * 0.28 + shore * 0.18 * ripple, 0.0, 0.96);
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	METALLIC = 0.0;
}
