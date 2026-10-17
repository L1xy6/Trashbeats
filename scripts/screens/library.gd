class_name LibraryScreen
extends Control
## 03 乐器库 — trash instrument cards with tap-to-preview and animated EQ bars.

signal request_screen(idx: int)

var _eq_bars = {}      # track -> Array[ColorRect]
var _eq_until = {}     # track -> float (Time ticks msec deadline)
var _badges = []
var _grid = null       # the instrument grid container (rebuilt on custom_sounds_changed)

func _ready() -> void:
	UIKit.full_rect(self)

	var margin = MarginContainer.new()
	UIKit.full_rect(margin)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	root.add_child(UIKit.label("核心功能 · 垃圾乐器库 / INSTRUMENT LIBRARY", 13, UIKit.COL_MUTED))
	root.add_child(UIKit.label("每个垃圾一张卡片,点一下就能听", 30, UIKit.COL_NEON))
	root.add_child(UIKit.label("同种垃圾也有不同音色(铁质 / 铝制 / 踩扁的易拉罐…),集齐材质解锁成就。", 15, UIKit.COL_TEXT))

	var grid = HBoxContainer.new()
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 16)
	root.add_child(grid)
	_grid = grid

	for inst in GameState.favorite_instruments():
		var t = GameState.global_track_of(inst.id)
		grid.add_child(_build_card(inst, t))

	var foot = UIKit.label("敲一下、亮一下、解锁一下 — 让收集本身就上瘾。", 14, UIKit.COL_MUTED)
	root.add_child(foot)

	GameState.collected_changed.connect(func(_id): _refresh_badges())
	GameState.custom_sounds_changed.connect(_rebuild)
	GameState.favorite_changed.connect(func(_id): call_deferred("_rebuild"))

func _build_card(inst: Dictionary, track: int) -> Control:
	var col: Color = inst.color

	var card = UIKit.panel(UIKit.COL_PANEL, UIKit.COL_BORDER, 2, 8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(240, 160)
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	vb.add_child(UIKit.label(inst.mat, 13, col, true))
	vb.add_child(UIKit.label(inst.name, 18, UIKit.COL_TEXT))

	# equalizer bars
	var eq = HBoxContainer.new()
	eq.custom_minimum_size = Vector2(0, 90)
	eq.size_flags_vertical = Control.SIZE_EXPAND_FILL
	eq.alignment = BoxContainer.ALIGNMENT_END
	eq.add_theme_constant_override("separation", 6)
	var bars = []
	for i in 4:
		var bar = ColorRect.new()
		bar.color = col
		bar.color.a = 0.85
		bar.custom_minimum_size = Vector2(18, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_END
		eq.add_child(bar)
		bars.append(bar)
	vb.add_child(eq)
	_eq_bars[track] = bars
	_eq_until[track] = 0.0

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	var play_btn = UIKit.button("▶ 试听", col)
	play_btn.pressed.connect(func(): _preview(track))
	row.add_child(play_btn)

	var spacer = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var badge = UIKit.label("", 13, UIKit.COL_MUTED)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge)
	var is_custom = inst.get("custom", false)
	_badges.append({"label": badge, "id": inst.id, "color": col, "custom": is_custom})
	if is_custom:
		badge.text = "✓ 已处理 · 0.3s"
		badge.add_theme_color_override("font_color", col)

	var star = Button.new()
	star.pressed.connect(func(): _toggle_fav(inst.id))
	_update_star(star, inst.id)
	row.add_child(star)

	return card

func _toggle_fav(id: String) -> void:
	GameState.toggle_favorite(id)
	# defer rebuild so the clicked star button isn't freed mid-pressed-handler
	call_deferred("_rebuild")

func _update_star(star: Button, id: String) -> void:
	var fav = GameState.is_favorite(id)
	star.text = "★" if fav else "☆"
	star.add_theme_font_override("font", UIKit.cjk_font())
	star.add_theme_font_size_override("font_size", 20)
	star.add_theme_color_override("font_color", UIKit.COL_AI if fav else UIKit.COL_MUTED)
	star.add_theme_color_override("font_hover_color", UIKit.COL_BG)
	star.add_theme_color_override("font_pressed_color", UIKit.COL_BG)
	star.add_theme_stylebox_override("normal", UIKit.style_box(UIKit.COL_PANEL, UIKit.COL_BORDER, 1, 4))
	star.add_theme_stylebox_override("hover", UIKit.style_box(UIKit.COL_AI, UIKit.COL_AI, 1, 4))
	star.add_theme_stylebox_override("pressed", UIKit.style_box(UIKit.COL_AI.darkened(0.25), UIKit.COL_AI, 1, 4))
	star.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	star.custom_minimum_size = Vector2(36, 36)
	star.focus_mode = Control.FOCUS_NONE

func _rebuild() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	_eq_bars = {}
	_eq_until = {}
	_badges = []
	for inst in GameState.favorite_instruments():
		var t = GameState.global_track_of(inst.id)
		_grid.add_child(_build_card(inst, t))
	_refresh_badges()

func _refresh_badges() -> void:
	for b in _badges:
		if b.get("custom", false):
			continue
		var got: bool = GameState.collected.get(b.id, false)
		b.label.text = "✓ 已收集" if got else "· 未收集"
		b.label.add_theme_color_override("font_color", b.color if got else UIKit.COL_MUTED)

func _preview(track: int) -> void:
	Audio.trigger(track)
	_eq_until[track] = Time.get_ticks_msec() + 700

func _process(_delta: float) -> void:
	var now = Time.get_ticks_msec()
	for t in _eq_bars.keys():
		var active: bool = now < _eq_until[t] or (Audio.playing and Audio.current_step % 4 == 0)
		for i in _eq_bars[t].size():
			var bar: ColorRect = _eq_bars[t][i]
			if active:
				bar.custom_minimum_size.y = randf_range(10, 84)
			else:
				bar.custom_minimum_size.y = lerpf(bar.custom_minimum_size.y, 12.0, 0.2)

func on_enter() -> void:
	_refresh_badges()

func on_exit() -> void:
	pass
