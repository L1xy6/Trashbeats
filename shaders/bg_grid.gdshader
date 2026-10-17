/*
 * TrashBeats arcade background — neon perspective grid + drifting pixel dust.
 * Custom shader in the spirit of godotshaders.com synthwave grids.
 * Apply to a full-screen ColorRect behind everything.
 * Theme unified: grid + dust share the same neon green.
 */
shader_type canvas_item;

uniform vec4 bg_top : source_color = vec4(0.016, 0.024, 0.055, 1.0);
uniform vec4 bg_bottom : source_color = vec4(0.045, 0.016, 0.075, 1.0);
uniform vec4 grid_color : source_color = vec4(0.24, 1.0, 0.55, 1.0);
uniform vec4 dust_color : source_color = vec4(0.24, 1.0, 0.55, 1.0);  // unified
uniform float grid_alpha : hint_range(0.0, 1.0) = 0.14;
uniform vec2 grid_cells = vec2(28.0, 16.0);
uniform float scroll_speed = 0.35;

float hash21(vec2 p) {
	p = fract(p * vec2(234.34, 435.345));
	p += dot(p, p + 34.23);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;

	// vertical gradient base
	vec3 col = mix(bg_top.rgb, bg_bottom.rgb, uv.y);

	// subtle neon grid, gently scrolling
	vec2 g = uv * grid_cells + vec2(0.0, TIME * scroll_speed * 0.15);
	vec2 fw = fwidth(g);
	vec2 line = abs(fract(g - 0.5) - 0.5) / max(fw, vec2(1e-4));
	float grid = 1.0 - min(min(line.x, line.y), 1.0);
	// fade grid towards the top so text stays readable
	col += grid_color.rgb * grid * grid_alpha * smoothstep(0.15, 0.9, uv.y);

	// drifting pixel dust (sparse sparkle, like the web page's ambient dots)
	vec2 cell = floor(uv * grid_cells * 2.0 + vec2(0.0, TIME * scroll_speed));
	float h = hash21(cell);
	if (h > 0.985) {
		float twinkle = 0.5 + 0.5 * sin(TIME * (2.0 + h * 6.0) + h * 40.0);
		vec2 c = fract(uv * grid_cells * 2.0) - 0.5;
		float d = smoothstep(0.12, 0.0, length(c));
		col += dust_color.rgb * d * twinkle * 0.28;
	}

	COLOR = vec4(col, 1.0);
}
