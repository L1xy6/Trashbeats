extends Control
## Main — screen manager: shader background, screen stack, bottom nav,
## CRT overlay. Keyboard ←/→ switches screens like the web page's arrow nav.

const SCREEN_NAMES = ["封面", "寻宝", "乐器库", "编曲"]

var _screens = []
var _nav_btns = []
var _counter_lbl: Label
var _current = -1

func _ready() -> void:
	UIKit.full_rect(self)
	if OS.get_name() == "macOS":
		theme = Theme.new()
		theme.default_font = UIKit.cjk_font()

	# animated arcade background
	var bg = ColorRect.new()
	UIKit.full_rect(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg_mat = ShaderMaterial.new()
	bg_mat.shader = load("res://shaders/bg_grid.gdshader")
	bg.material = bg_mat
	add_child(bg)

	# screen stack
	var stack = Control.new()
	UIKit.full_rect(stack)
	add_child(stack)

	var cover = CoverScreen.new()
	var collect = CollectScreen.new()
	var library = LibraryScreen.new()
	var sequencer = SequencerScreen.new()
	_screens = [cover, collect, library, sequencer]
	for s in _screens:
		s.visible = false
		stack.add_child(s)
		s.request_screen.connect(_go_to)

	# bottom nav
	var nav = HBoxContainer.new()
	nav.anchor_top = 1.0
	nav.anchor_right = 1.0
	nav.anchor_bottom = 1.0
	nav.offset_top = -52
	nav.offset_bottom = -8
	nav.offset_left = 40
	nav.offset_right = -40
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 12)
	add_child(nav)

	for i in SCREEN_NAMES.size():
		var b = UIKit.button("%d %s" % [i + 1, SCREEN_NAMES[i]], UIKit.COL_MUTED, 14)
		b.custom_minimum_size = Vector2(130, 36)
		b.pressed.connect(_go_to.bind(i))
		nav.add_child(b)
		_nav_btns.append(b)

	_counter_lbl = UIKit.label("", 13, UIKit.COL_MUTED)
	_counter_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.add_child(_counter_lbl)
	GameState.collected_changed.connect(func(_id): _refresh_counter())
	_refresh_counter()

	# CRT overlay (topmost, ignores input)
	var crt = ColorRect.new()
	UIKit.full_rect(crt)
	crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var crt_mat = ShaderMaterial.new()
	crt_mat.shader = load("res://shaders/crt_overlay.gdshader")
	crt.material = crt_mat
	add_child(crt)

	_go_to(0)

func _refresh_counter() -> void:
	_counter_lbl.text = "乐器 %d/%d" % [GameState.collected_count(), GameState.INSTRUMENTS.size()]

func _go_to(idx: int) -> void:
	if idx == _current:
		return
	if _current >= 0:
		_screens[_current].on_exit()
		_screens[_current].visible = false
	_current = idx
	var s: Control = _screens[idx]
	s.visible = true
	s.modulate.a = 0.0
	s.on_enter()
	var tw = create_tween()
	tw.tween_property(s, "modulate:a", 1.0, 0.25)
	for i in _nav_btns.size():
		var accent = UIKit.COL_NEON if i == idx else UIKit.COL_MUTED
		_nav_btns[i].add_theme_color_override("font_color", accent)
		_nav_btns[i].add_theme_stylebox_override("normal", UIKit.style_box(UIKit.COL_PANEL, accent, 2, 4))

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_RIGHT or ev.keycode == KEY_DOWN or ev.keycode == KEY_SPACE:
			_go_to(mini(_current + 1, _screens.size() - 1))
		elif ev.keycode == KEY_LEFT or ev.keycode == KEY_UP:
			_go_to(maxi(_current - 1, 0))
