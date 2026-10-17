class_name CollectScreen
extends Control
## 02 音色试听 — 直接试听四种垃圾变身的程序化音色。
##
## 后续将在此页面新增「用户自己录音 → AI 降噪 → 入库」栏目，
## 复用本文件保留的 Recorder（麦克风）相关逻辑。

signal request_screen(idx: int)

# 录音标准化模块（用 preload 加载，不依赖 Godot 全局 class_name 扫描）
const SOUND_EDIT := preload("res://scripts/sound_edit.gd")

# Microphone recorder (created in on_enter, torn down in on_exit).
# 预留给后续的「自己录音 → AI 降噪 → 入库」栏目使用。
var _recorder: Recorder = null
var _recorder_available = false

# 页面内的动态容器引用（用于收藏 / 删除后刷新）
var _preview_hb: HBoxContainer
var _sounds_hb: HBoxContainer

# 自定义上传栏的临时状态
var _pending_samples: PackedFloat32Array = PackedFloat32Array()
var _pending_image: String = ""
var _recording_now: bool = false
var _name_input: LineEdit
var _rec_btn: Button
var _ok_btn: Button
var _img_texture: TextureRect
var _file_dialog: FileDialog

func _ready() -> void:
	UIKit.full_rect(self)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 16)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# 整页竖向滚动：内容（4 试听卡 + 自定义上传 + 我的声音）较高时保证底部「我的声音」可滚到
	var scroll = ScrollContainer.new()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(root)

	var margin = MarginContainer.new()
	UIKit.full_rect(margin)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 64)
	margin.add_child(scroll)
	add_child(margin)

	var eyebrow = UIKit.label("音色试听 · 四种垃圾变身你的乐器 / SOUND LIBRARY", 13, UIKit.COL_MUTED)
	root.add_child(eyebrow)

	var title_lbl = UIKit.label("已有音色试听", 30, UIKit.COL_NEON)
	root.add_child(title_lbl)

	_preview_hb = HBoxContainer.new()
	_preview_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	_preview_hb.add_theme_constant_override("separation", 16)
	root.add_child(_preview_hb)

	for t in GameState.INSTRUMENTS.size():
		_preview_hb.add_child(_build_preview_card(t))

	# ── 自定义上传：录制你的专属声音（静态 UI，功能后续接入）──
	var custom_card = UIKit.panel(UIKit.COL_PANEL, UIKit.COL_AI, 2, 8)
	custom_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cvb = VBoxContainer.new()
	cvb.add_theme_constant_override("separation", 12)
	custom_card.add_child(cvb)

	var custom_title = UIKit.label("自定义上传 · 录制你的专属声音", 22, UIKit.COL_AI)
	cvb.add_child(custom_title)

	# 名称输入 + 录制键
	var row1 = HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	cvb.add_child(row1)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "给你的垃圾起个名字，如：生锈铁罐"
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.add_theme_font_override("font", UIKit.cjk_font())
	_name_input.add_theme_font_size_override("font_size", 15)
	_name_input.add_theme_color_override("font_color", UIKit.COL_TEXT)
	_name_input.add_theme_color_override("font_placeholder_color", UIKit.COL_MUTED)
	_name_input.add_theme_stylebox_override("normal", UIKit.style_box(UIKit.COL_BG, UIKit.COL_BORDER, 1, 4))
	row1.add_child(_name_input)

	_ok_btn = UIKit.button("确定", UIKit.COL_AI)
	_ok_btn.pressed.connect(_on_confirm)
	row1.add_child(_ok_btn)

	_rec_btn = UIKit.button("🎙 录制", UIKit.COL_AI)
	_rec_btn.pressed.connect(_on_record_toggle)
	row1.add_child(_rec_btn)

	# 图片上传（选填，支持本地图片，无需拍照）
	var row2 = HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	cvb.add_child(row2)

	var img_btn = UIKit.button("🖼 上传图片（选填）", UIKit.COL_AI)
	img_btn.pressed.connect(_open_file_dialog)
	row2.add_child(img_btn)

	# 选中的图片缩略图（默认隐藏）
	_img_texture = TextureRect.new()
	_img_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_img_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_img_texture.custom_minimum_size = Vector2(64, 64)
	_img_texture.visible = false
	cvb.add_child(_img_texture)

	root.add_child(custom_card)

	# ── 我的声音：已上传的自定义声音（含试听 / 收藏 / 删除）──
	var sounds_card = UIKit.panel(UIKit.COL_PANEL, UIKit.COL_AI, 2, 8)
	sounds_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var svb = VBoxContainer.new()
	svb.add_theme_constant_override("separation", 12)
	sounds_card.add_child(svb)
	svb.add_child(UIKit.label("我的声音", 22, UIKit.COL_AI))
	_sounds_hb = HBoxContainer.new()
	_sounds_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	_sounds_hb.add_theme_constant_override("separation", 16)
	svb.add_child(_sounds_hb)
	root.add_child(sounds_card)

	_rebuild_sounds()
	GameState.favorite_changed.connect(func(_id): call_deferred("_rebuild_preview"); call_deferred("_rebuild_sounds"))
	GameState.custom_sounds_changed.connect(func(): call_deferred("_rebuild_sounds"))

func _process(_delta: float) -> void:
	if _recorder:
		_recorder.process()

# ── 试听卡片（无拍照/录音，点开即听）──────────────────────────────

func _build_preview_card(track: int) -> Control:
	var inst: Dictionary = GameState.INSTRUMENTS[track]
	var col: Color = inst.color

	var card = UIKit.panel(UIKit.COL_PANEL, UIKit.COL_BORDER, 2, 8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 160)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	vb.add_child(UIKit.label(inst.mat, 13, col, true))
	vb.add_child(UIKit.label(inst.name, 18, UIKit.COL_TEXT))

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	var btn = UIKit.button("▶ 试听", col)
	btn.pressed.connect(func(): Audio.trigger(track))
	row.add_child(btn)

	row.add_child(_make_fav_star(inst.id))

	return card

# ── 页面刷新 / 我的声音板块 ─────────────────────────────────────────

func _rebuild_preview() -> void:
	if _preview_hb == null:
		return
	for c in _preview_hb.get_children():
		c.queue_free()
	for t in GameState.INSTRUMENTS.size():
		_preview_hb.add_child(_build_preview_card(t))

func _rebuild_sounds() -> void:
	if _sounds_hb == null:
		return
	for c in _sounds_hb.get_children():
		c.queue_free()
	if GameState.custom_sounds.is_empty():
		var hint = UIKit.label("还没有你的声音，去上面的『自定义上传』录一段吧 🎙", 15, UIKit.COL_MUTED)
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sounds_hb.add_child(hint)
		return
	for cs in GameState.custom_sounds:
		_sounds_hb.add_child(_build_sound_card(cs))

func _build_sound_card(cs: Dictionary) -> Control:
	var col: Color = cs.color

	var card = UIKit.panel(UIKit.COL_PANEL, UIKit.COL_BORDER, 2, 8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 220)

	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	vb.add_child(UIKit.label("你的录音 · 已处理 ✓", 13, col, true))
	vb.add_child(UIKit.label(cs.name, 18, UIKit.COL_TEXT))
	vb.add_child(UIKit.label("0.3s 标准节奏", 12, UIKit.COL_MUTED))

	# 入库时附带的图片（若有）显示在卡片里
	var img_path: String = cs.get("image", "")
	if img_path != "":
		var tex = TextureRect.new()
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(64, 64)
		var img = Image.new()
		if img.load(img_path) == OK:
			tex.texture = ImageTexture.create_from_image(img)
		vb.add_child(tex)

	var play_btn = UIKit.button("▶ 试听", col)
	play_btn.pressed.connect(func(): Audio.trigger(GameState.global_track_of(cs.id)))
	vb.add_child(play_btn)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	row.add_child(_make_fav_star(cs.id))

	var del = UIKit.button("🗑 删除", UIKit.COL_AI)
	del.pressed.connect(func(): _delete_sound(cs.id))
	row.add_child(del)

	return card

## Build a ★/☆ favorite toggle button (shared by preset & custom sound cards).
func _make_fav_star(id: String) -> Button:
	var star = Button.new()
	star.pressed.connect(func(): GameState.toggle_favorite(id))
	_update_star_btn(star, id)
	return star

func _update_star_btn(star: Button, id: String) -> void:
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

func _delete_sound(id: String) -> void:
	GameState.remove_custom_sound(id)
	Audio.reload_recorded_samples()
	UIKit.toast(self, "已删除该声音", UIKit.COL_AI)

# ── 自定义上传：录音 / 图片 / 入库 ──────────────────────────────────

func _on_record_toggle() -> void:
	if Recorder.is_capture_supported() and not _recording_now:
		if _recorder == null:
			_recorder = Recorder.new()
		if not _recorder.available():
			_recorder_available = _recorder.setup(self)
	if _recorder == null or not Recorder.is_capture_supported():
		UIKit.toast(self, "网页版不支持录音，请用桌面端 Godot 演示", UIKit.COL_AI)
		return
	if not _recording_now:
		_recorder.start_recording()
		_recording_now = true
		_rec_btn.text = "■ 停止"
	else:
		var samples = _recorder.stop_recording()
		_recorder.teardown()
		_recorder_available = false
		_recording_now = false
		_rec_btn.text = "🎙 录制"
		if samples.size() == 0:
			UIKit.toast(self, "没录到声音，再试一次", UIKit.COL_AI)
			return
		# 1) 先播原始录音（让用户听到自己录了什么，仅此处能听原始版）
		Audio.play_sample(samples.duplicate())
		# 2) 后台标准化：降噪 + 压成 0.3s 标准节奏（"我的声音"/乐器库都用这版）
		UIKit.toast(self, "正在处理中…", UIKit.COL_AI)
		var processed = SOUND_EDIT.process_hit(samples, Recorder.SAMPLE_RATE)
		_pending_samples = processed
		# 让「处理中」提示停留片刻，便于感知（处理本身已完成）
		await get_tree().create_timer(0.6).timeout
		UIKit.toast(self, "✅ 已标准化为 0.3s 节奏，点『确定』入库", UIKit.COL_AI)

func _on_confirm() -> void:
	var nm = _name_input.text.strip_edges()
	if nm == "":
		UIKit.toast(self, "先给垃圾起个名字", UIKit.COL_AI)
		return
	if _pending_samples.size() == 0:
		UIKit.toast(self, "先录一段声音", UIKit.COL_AI)
		return
	var dir = "user://samples"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_absolute(dir)
	var fid = GameState.next_custom_id()
	var final_path = "%s/%s.wav" % [dir, fid]
	_recorder.save_wav(final_path, _pending_samples)
	var entry = GameState.add_custom_sound(nm, _pending_image, final_path, Color("ffcf5c"), fid)
	var track = GameState.global_track_of(entry.id)
	Audio.load_sample_from_array(track, _pending_samples)
	_pending_samples = PackedFloat32Array()
	_pending_image = ""
	_name_input.text = ""
	if _img_texture != null and is_instance_valid(_img_texture):
		_img_texture.texture = null
		_img_texture.visible = false
	UIKit.toast(self, "已加入声音库（0.3s 标准节奏）：%s" % nm, UIKit.COL_AI)
	# 入库即刻刷新“我的声音”与顶部收藏星，不等信号时序
	_rebuild_sounds()
	_rebuild_preview()

func _open_file_dialog() -> void:
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp,*.bmp ; 图片"])
		_file_dialog.file_selected.connect(_on_image_selected)
		add_child(_file_dialog)
	_file_dialog.popup_centered(Vector2i(700, 500))

func _on_image_selected(path: String) -> void:
	_pending_image = path
	var img = Image.new()
	if img.load(path) == OK:
		_img_texture.texture = ImageTexture.create_from_image(img)
		_img_texture.visible = true
	UIKit.toast(self, "已选图片（选填）", UIKit.COL_AI)

# ── 生命周期 ────────────────────────────────────────────────────────

func on_enter() -> void:
	# No device is opened just by visiting the sound library.
	_pending_samples = PackedFloat32Array()
	_recording_now = false
	_rec_btn.text = "🎙 录制"
	# 进入第 2 页时重置上传区（上次残留的图片/录音不滞留）
	_pending_image = ""
	if _img_texture != null and is_instance_valid(_img_texture):
		_img_texture.texture = null
		_img_texture.visible = false
	# 进入第 2 页时刷新「我的声音」列表与顶部收藏星，保证显示最新状态
	_rebuild_sounds()
	_rebuild_preview()

func on_exit() -> void:
	if _recorder:
		_recorder.teardown()
		_recorder = null
		_recorder_available = false
