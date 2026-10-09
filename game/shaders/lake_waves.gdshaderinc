// Shared analytic lake surface. water.gd evaluates the same function on the CPU,
// so floating objects, wheels and the visible surface agree on the water height.
const float LAKE_WAVE_AMPLITUDE = 0.045;

float lake_wave(vec2 p, float t) {
	return LAKE_WAVE_AMPLITUDE * (sin(p.x * 0.42 + p.y * 0.17 + t * 1.3) + 0.6 * sin(p.x * 0.19 - p.y * 0.37 + t * 0.9)) / 1.6;
}

vec2 lake_wave_gradient(vec2 p, float t) {
	float a = cos(p.x * 0.42 + p.y * 0.17 + t * 1.3);
	float b = cos(p.x * 0.19 - p.y * 0.37 + t * 0.9);
	return LAKE_WAVE_AMPLITUDE / 1.6 * vec2(a * 0.42 + 0.6 * b * 0.19, a * 0.17 - 0.6 * b * 0.37);
}
