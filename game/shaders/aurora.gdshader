shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;

// Northern lights (scripts/core/aurora.gd): tall curtains hanging in the night
// sky. Each curtain is a ribbon of columns, UV.x along it (0..1), UV.y from its
// lower edge to its top; UV2 = (length in metres, seed); NORMAL is the
// horizontal direction the curtain folds in.
// - The curtain folds: slow waves travel along it and bend it sideways, and
//   where a fold turns edge-on to the viewer the light piles up brighter.
// - Rays: thin vertical streaks of uneven height drift along the curtain.
// - Colour by height, as oxygen and nitrogen glow: a sharp green lower edge,
//   green fading upward into a faint crimson top, a pink fringe under the
//   edge while the display surges.
uniform float level = 0.0;     // 0 nothing .. 1 full display (fades in and out)
uniform float surge = 0.0;     // 0 calm .. 1 a bright, fast, pink-edged burst
uniform float fold = 1.0;      // scale of the sideways folds
uniform vec3 green = vec3(0.16, 1.0, 0.48);
uniform vec3 crimson = vec3(0.62, 0.1, 0.42);
uniform vec3 pink = vec3(1.0, 0.25, 0.62);

varying float edge_on;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

// Smooth 1D value noise, 0..1.
float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(i), hash(i + 1.0), f);
}

float folds(float x, float seed, float t) {
	return 46.0 * sin(x * 0.0055 + t * 0.045 + seed)
		+ 21.0 * sin(x * 0.016 - t * 0.09 + seed * 2.3)
		+ 8.0 * sin(x * 0.043 + t * 0.21 + seed * 4.1);
}

void vertex() {
	float x = UV.x * UV2.x;
	float seed = UV2.y;
	float t = TIME * (1.0 + surge * 1.5);
	VERTEX += NORMAL * folds(x, seed, t) * fold;
	// Slope of the fold: a curtain bent towards the line of sight is seen
	// through a longer path of glowing air.
	float slope = (folds(x + 4.0, seed, t) - folds(x - 4.0, seed, t)) / 8.0 * fold;
	edge_on = clamp(abs(slope) * 0.6, 0.0, 0.8);
}

void fragment() {
	float x = UV.x * UV2.x;
	float v = UV.y;
	float seed = UV2.y;
	float t = TIME * (1.0 + surge * 1.5);
	// Rays drifting along the curtain, three octaves of streaks.
	float drift = t * (2.5 + surge * 6.0);
	float rays = noise(x * 0.045 + drift * 0.02 + seed * 9.0) * 0.5
		+ noise(x * 0.13 - drift * 0.05 + seed * 3.0) * 0.32
		+ noise(x * 0.37 + drift * 0.11) * 0.18;
	rays = mix(0.25, 1.15, rays * rays);
	// Lower edge wavers a little, rays reach different heights.
	float bottom = 0.02 + 0.06 * noise(x * 0.008 + t * 0.06 + seed);
	float top = 0.45 + 0.5 * noise(x * 0.02 - t * 0.03 + seed * 5.0);
	float above = max(v - bottom, 0.0);
	float lower = smoothstep(bottom, bottom + 0.035, v);
	float glow_green = lower * exp(-above * 3.4 / top) * (1.0 - smoothstep(top * 0.85, top + 0.12, v));
	float glow_red = lower * smoothstep(0.25, 0.75, v) * (1.0 - smoothstep(0.75, 1.0, v)) * 0.22;
	float fringe = smoothstep(bottom - 0.03, bottom, v) * (1.0 - smoothstep(bottom, bottom + 0.03, v)) * surge * 0.55;
	// Brightness waves running along the curtain and its faded ends.
	float pulse = 0.55 + 0.45 * noise(x * 0.004 - t * (0.35 + surge * 0.9) + seed * 2.0);
	float ends = smoothstep(0.0, 0.18, UV.x) * (1.0 - smoothstep(0.82, 1.0, UV.x));
	float strength = level * ends * pulse * (0.7 + edge_on * 0.5) * (0.75 + surge * 0.5);
	vec3 light = green * glow_green * rays + crimson * glow_red * mix(0.6, 1.0, rays) + pink * fringe * rays;
	light *= strength;
	// Added onto the sky as colour * alpha: the hue in ALBEDO, the amount in ALPHA.
	float peak = max(max(light.r, light.g), max(light.b, 0.0001));
	ALBEDO = light / peak;
	ALPHA = min(peak, 1.0);
}
