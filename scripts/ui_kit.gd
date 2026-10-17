class_name UIKit
extends RefCounted
## Shared arcade UI helpers: fonts, palette, styled controls.

const COL_BG = Color("070b12")
const COL_PANEL = Color("0e1420")
const COL_BORDER = Color("1e2a3a")
const COL_TEXT = Color("e8f2ea")
const COL_MUTED = Color("8fa3b0")
# ── Single distinctive theme color: neon green. All accents derive from it. ──
const COL_NEON = Color("7dff6a")
const COL_CYAN = Color("7dff6a")   # unified — was cyan
const COL_PINK = Color("7dff6a")   # unified — was pink
const COL_AI = Color("5cdb4a")     # deeper green for AI-note distinction only

static var _pixel: Font = null
static var _cjk: Font = null

static func cjk_font() -> Font:
	if _cjk == null:
		var sf = SystemFont.new()
		sf.font_names = ["Microsoft YaHei", "Noto Sans SC", "PingFang SC", "Segoe UI Emoji", "sans-serif"]
		sf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
		_cjk = sf
	return _cjk

## Press Start 2P for Latin accents, with CJK fallback so mixed headings work.
static func pixel_font() -> Font:
	if _pixel == null:
		if ResourceLoader.exists("res://fonts/PressStart2P-Regular.ttf"):
			var pf: FontFile = load("res://fonts/PressStart2P-Regular.ttf")
			pf.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
			pf.fallbacks = [cjk_font()]
			_pixel = pf
		else:
			_pixel = cjk_font()
	return _pixel

static func label(text: String, size: int, color: Color = COL_TEXT, use_pixel: bool = false) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_font_override("font", pixel_font() if use_pixel else cjk_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func style_box(bg: Color, border: Color, border_w: int = 2, radius: int = 6) -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb

static func button(text: String, accent: Color = COL_NEON, font_size: int = 15) -> Button:
	var b = Button.new()
	b.text = text
	b.add_theme_font_override("font", cjk_font())
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", accent)
	b.add_theme_color_override("font_hover_color", COL_BG)
	b.add_theme_color_override("font_pressed_color", COL_BG)
	b.add_theme_stylebox_override("normal", style_box(COL_PANEL, accent, 2, 4))
	b.add_theme_stylebox_override("hover", style_box(accent, accent, 2, 4))
	b.add_theme_stylebox_override("pressed", style_box(accent.darkened(0.25), accent, 2, 4))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

static func panel(bg: Color = COL_PANEL, border: Color = COL_BORDER, border_w: int = 2, radius: int = 6) -> PanelContainer:
	var p = PanelContainer.new()
	p.add_theme_stylebox_override("panel", style_box(bg, border, border_w, radius))
	return p

## Anchor a control to fill its parent completely. (set_anchors_preset's
## resize modes derive offsets from current/min size, which zeroes out
## freshly-created controls — setting anchors and offsets directly avoids it.)
static func full_rect(c: Control) -> void:
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0

## Transient toast message that fades in, holds, fades out.
static func toast(parent: Control, text: String, accent: Color = COL_NEON) -> void:
	var l = label(text, 15, accent)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	full_rect(l)
	l.offset_bottom = 44
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	var tw = l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)
