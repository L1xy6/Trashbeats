/*
 * CRT overlay for TrashBeats — stripped down for text readability.
 * Keeps only a whisper of chromatic aberration (the user likes it)
 * and a gentle vignette. No pixelation, no scanlines, no warp, no noise.
 * Apply to a full-screen ColorRect (mouse_filter = IGNORE) as an overlay.
 */
shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

uniform float aberration : hint_range(-1.0, 1.0) = 0.0;
uniform float vignette_opacity : hint_range(0.0, 1.0) = 0.18;

void fragment() {
	vec2 uv = SCREEN_UV;

	// Barely-there chromatic aberration — a hint of retro, text stays sharp
	vec4 text;
	text.r = texture(SCREEN_TEXTURE, uv + vec2(aberration, 0.0)).r;
	text.g = texture(SCREEN_TEXTURE, uv - vec2(aberration, 0.0)).g;
	text.b = texture(SCREEN_TEXTURE, uv).b;
	text.a = 1.0;

	// Gentle vignette — darkens edges only, center text is untouched
	vec2 v = uv * (1.0 - uv);
	float vig = pow(v.x * v.y * 15.0, vignette_opacity * 0.5);
	text.rgb *= vig;

	COLOR = text;
}
