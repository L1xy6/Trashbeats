class_name SequencerScreen
extends Control
## 04 编曲 — 16-step sequencer (the interactive core).
## 双模式：
##   · LIST  —— 点底部"编曲"先进这里，显示所有编曲项目 + 新建
##   · EDIT  —— 打开某个项目（或新建后）才进格子
## Click cells to place notes, drag vertically on an active cell to tune its
## pitch, and let "智能续写" continue from your seed notes.

signal request_screen(idx: int)

const STEPS = 16

# Default groove, mirroring the patterns in index.html (kept for reference;
# new projects start blank — Phase 2 design choice).
const DEFAULT_PATTERNS = [
	[1,0,0,0,1,0,1,0,1,0,0,0,1,0,1,0],  # 易拉罐 808
	[0,0,1,0,0,0,1,0,0,0,1,0,0,1,1,0],  # 塑料瓶 木鱼
	[0,0,0,0,1,0,0,0,0,0,0,0,1,0,0,1],  # 玻璃瓶 铃
	[0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1],  # 纸箱 闷鼓
]

class SeqCell extends Control:
	signal changed(cell: SeqCell)

	var track = 0
	var step = 0
	var div = 4        # 每拍格数（4 = 常规，3 = 三连音），用于拍点标记
	var on = false
	var ai = false
	var pitch = 0
	var col = Color.WHITE
	var playing_col = false

	var _press_pos = Vector2.ZERO
	var _press_pitch = 0
	var _dragging = false
	var _armed = false

	func _init(p_track: int, p_step: int, p_col: Color) -> void:
		track = p_track
		step = p_step
		col = p_col
		custom_minimum_size = Vector2(46, 52)

	func set_note(p_on: bool, p_ai: bool = false, p_pitch: int = 0) -> void:
		on = p_on
		ai = p_ai and p_on
		pitch = p_pitch if p_on else 0
		queue_redraw()

	func pulse() -> void:
		pivot_offset = size / 2.0
		var tw = create_tween()
		tw.tween_property(self, "scale", Vector2(1.12, 1.12), 0.05)
		tw.tween_property(self, "scale", Vector2.ONE, 0.15)

	func _draw() -> void:
		var r = Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var bg = Color("141c2a")
		var border = Color("26334a")
		if on:
			if ai:
				bg = UIKit.COL_AI.darkened(0.72)
				border = UIKit.COL_AI
			else:
				bg = col.darkened(0.45)
				border = col
		if playing_col:
			bg = bg.lightened(0.35)
		draw_rect(r, bg, true)
		draw_rect(r, border, false, 2.0)
		if on:
			# pitch indicator: bright inner block shifts up/down with pitch
			var off = -float(pitch) * 2.2
			var inner = Rect2(
				Vector2(r.position.x + 8, r.get_center().y - 5 + off),
				Vector2(r.size.x - 16, 10))
			draw_rect(inner, UIKit.COL_AI if ai else col, true)
		elif step % div == 0:
			# beat marker tick on empty downbeats
			draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(4, 4)), Color("2c3c55"), true)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				if not on:
					# press on empty cell: place note immediately
					set_note(true, false, 0)
					_armed = true
					changed.emit(self)
				else:
					_press_pos = ev.position
					_press_pitch = pitch
					_dragging = false
			else:
				if _armed:
					# this press placed the note; releasing must not remove it
					_armed = false
				elif on and not _dragging:
					set_note(false)
					changed.emit(self)
				_dragging = false
		elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_RIGHT and ev.pressed:
			if on:
				set_note(false)
				changed.emit(self)
		elif ev is InputEventMouseMotion and on and not _armed and ev.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var dy: float = ev.position.y - _press_pos.y
			if absf(dy) > 8.0:
				_dragging = true
			if _dragging:
				var p = clampi(_press_pitch + int(round(-dy / 14.0)), -6, 6)
				if p != pitch:
					pitch = p
					queue_redraw()
					changed.emit(self)

## 旋律波形音轨：显示波形 + 强拍标记 + 播放头；点击标记强拍（第 1 个为对齐锚点）。
class MelodyWave extends Control:
	signal mark_added(t: float)

	var peaks := PackedFloat32Array()
	var duration := 0.0
	var marks: Array = []
	var playhead := -1.0
	var pps := 6.0        # 基础像素/秒
	var zoom := 1.0
	const H := 92.0

	func setup(p_peaks: PackedFloat32Array, p_duration: float, p_marks: Array, p_zoom: float) -> void:
		peaks = p_peaks
		duration = p_duration
		marks = p_marks.duplicate()
		zoom = p_zoom
		_relayout()

	func set_marks(p_marks: Array) -> void:
		marks = p_marks.duplicate()
		queue_redraw()

	func set_playhead(t: float) -> void:
		playhead = t
		queue_redraw()

	func set_zoom(z: float) -> void:
		zoom = clampf(z, 1.0, 16.0)
		_relayout()

	func _relayout() -> void:
		var w = maxf(1.0, duration) * pps * zoom
		custom_minimum_size = Vector2(w, H)
		size = custom_minimum_size
		queue_redraw()

	func _draw() -> void:
		var w = size.x
		var mid = H * 0.5
		draw_rect(Rect2(Vector2.ZERO, Vector2(w, H)), Color("0e1420"), true)
		var n = peaks.size()
		if n > 0 and duration > 0.0:
			var eff = pps * zoom
			var wc = Color("AFA9EC")
			var xstep = maxf(1.0, w / 2400.0)  # 限制绘制的列数,高倍缩放下也保持流畅
			var x = 0.0
			while x < w:
				var t = x / eff
				var idx = clampi(int(t / duration * n), 0, n - 1)
				var a = peaks[idx] * (H * 0.46)
				draw_line(Vector2(x, mid - a), Vector2(x, mid + a), wc, xstep)
				x += xstep
		# 强拍标记（第 1 个为锚点=绿；其余=橙）
		for i in marks.size():
			var mx = float(marks[i]) * pps * zoom
			var col = Color("1D9E75") if i == 0 else Color("D85A30")
			draw_line(Vector2(mx, 0), Vector2(mx, H), col, 2.0)
		# 播放头
		if playhead >= 0.0:
			var px = playhead * pps * zoom
			draw_line(Vector2(px, 0), Vector2(px, H), Color("dfe6f3"), 1.5)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if duration > 0.0:
				var t = clampf(ev.position.x / (pps * zoom), 0.0, duration)
				mark_added.emit(t)

const NOISE_SUPPRESSOR := preload("res://scripts/noise_cancelation/noise_suppressor.gd")
const MODE_LIST = 0
const MODE_EDIT = 1

var _mode = MODE_LIST
var _list_container: Control
var _edit_container: Control
var _current_pid: String = ""
var _tracks: Array = []   # instrument ids for the current project (row order)
var _cells = []           # [row][step] -> SeqCell  (row aligns with _tracks)
var _bpm_edit: LineEdit
var _status_label: Label
var _play_btn: Button
var _name_edit: LineEdit
var _prev_col = -1
var _add_menu: PopupMenu
var _addable_ids: Array = []
var _recorded_audio: PackedFloat32Array = PackedFloat32Array()   # 本项目"已录制"的音频（单声道 float32）
var _rec_dialog: FileDialog
var _steps = 16                 # 当前项目每循环步数：16 或 12（建项目时定死，均为 4 拍/循环）
var _div = 4                    # 每拍格数 = _steps / 4：4 = 常规（1/4 拍/格），3 = 三连音（1/3 拍/格）
var _ai_snapshot = []          # 续写前全量格子状态，供「取消智能续写」恢复
var _ai_undo_btn: Button = null
var _meter_menu: PopupMenu      # 新建编曲时选拍号
var _recording_step_count = 0   # 录制中累计步数（用于自动停止）
const REC_LOOP_LIMIT = 4        # 最多录 4 个循环自动停（=64 步）
var _rec_btn: Button

# ── 麦克风录制轨（Stage A）──────────────────────────────
var _recorder: Recorder = null                       # 麦克风捕获实例（_ready 里 setup 一次）
var _mic_audio: PackedFloat32Array = PackedFloat32Array()   # 本项目麦克风录制（单声道 float32）
var _mic_path: String = ""                           # 麦克风 wav 路径（user://projects/<id>_mic.wav）
var _mic_recording: bool = false                     # 是否正在录麦克风
var _mic_step_count: int = 0                         # 录制中累计步数（用于自动停止）
var _mic_rec_btn: Button = null                      # 麦克风区块里的 ● 录制 / ■ 停止 按钮
var _mic_dialog: FileDialog = null                   # 麦克风导出对话框

# ── AI 旋律生成（阶段 5）────────────────────────────────
const MELODY_GENERATOR := preload("res://scripts/melody_generator.gd")
var _melody_gen: Node                  # MelodyGenerator 实例（常驻）
var _melody_holder: VBoxContainer      # 旋律区块容器（表单 + 播放器）
var _rhythm_vb: Control = null          # 节奏区容器（格子+提示+已录制轨），rec 重建时挂这里
var _mic_vb: Control = null             # 麦克风区容器，mic 重建时挂这里
var _melody_path = ""                  # 本项目旋律 mp3（user://projects/<id>_melody.mp3）
var _melody_tags = ""                  # 生成时用的风格描述（供显示）
var _style_edit: LineEdit
var _lyrics_edit: LineEdit
var _melody_status: Label
var _melody_gen_btn: Button
var _melody_play_btn: Button
var _melody_progress: ProgressBar
var _melody_dialog: FileDialog
var _import_dialog: FileDialog
var _melody_tick: Timer
var _generating = false
var _gen_elapsed = 0.0
var _downbeat_marks: Array = []        # 强拍标记（秒，升序）；第 1 个为对齐锚点
var _rhythm_sync_pending = false       # 阶段5:点播放后旋律从头起播,节奏挂起到第一个强拍再进
var _sync_anchor = 0.0                 # 对齐锚点（秒）= _downbeat_marks[0]
var _melody_wave: Control = null       # 波形音轨控件
var _melody_bpm_label: Label = null    # 反推 BPM 显示
var _melody_wave_zoom = 1.0            # 波形缩放倍数
var _step_labels: Array = []           # 步骤引导标签引用（每次重建清空）
var _melody_bpm_applied = false       # 步骤③：是否已把旋律 BPM 应用到节奏

func _ready() -> void:
	UIKit.full_rect(self)

	var margin = MarginContainer.new()
	UIKit.full_rect(margin)
	margin.add_theme_constant_override("margin_left", 40)
	margin.add_theme_constant_override("margin_right", 40)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)

	var root = VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_list_container = VBoxContainer.new()
	_list_container.add_theme_constant_override("separation", 12)
	_list_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_list_container)

	_edit_container = VBoxContainer.new()
	_edit_container.add_theme_constant_override("separation", 12)
	_edit_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit_container.visible = false
	root.add_child(_edit_container)

	Audio.step_changed.connect(_on_step)
	Audio.transport_changed.connect(_on_transport)

	_add_menu = PopupMenu.new()
	add_child(_add_menu)
	_add_menu.id_pressed.connect(_on_add_track_selected)

	_rec_dialog = FileDialog.new()
	_rec_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_rec_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_rec_dialog.filters = PackedStringArray(["*.wav ; WAV 音频"])
	_rec_dialog.current_file = "trashbeats-recording.wav"
	_rec_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	_rec_dialog.file_selected.connect(_on_rec_save_selected)
	add_child(_rec_dialog)

	_mic_dialog = FileDialog.new()
	_mic_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_mic_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_mic_dialog.filters = PackedStringArray(["*.wav ; WAV 音频"])
	_mic_dialog.current_file = "trashbeats-mic.wav"
	_mic_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	_mic_dialog.file_selected.connect(_on_mic_save_selected)
	add_child(_mic_dialog)

	_meter_menu = PopupMenu.new()
	_meter_menu.add_theme_font_override("font", UIKit.cjk_font())
	_meter_menu.add_item("4/4 拍 · 16 格（4 组 × 4 · 每格 1/4 拍）", 16)
	_meter_menu.add_item("三连音 · 12 格（4 组 × 3 · 每格 1/3 拍）", 12)
	_meter_menu.id_pressed.connect(_create_project_with_steps)
	add_child(_meter_menu)

	# ── AI 旋律：生成器 + 导出对话框 + 刷新计时器 ──
	_melody_gen = MELODY_GENERATOR.new()
	add_child(_melody_gen)
	_melody_gen.task_submitted.connect(_on_melody_submitted)
	_melody_gen.download_complete.connect(_on_melody_downloaded)
	_melody_gen.error.connect(_on_melody_error)

	# Microphone capture starts only after the user presses Record.
	_recorder = null

	_melody_dialog = FileDialog.new()
	_melody_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_melody_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_melody_dialog.filters = PackedStringArray(["*.mp3 ; MP3 音频"])
	_melody_dialog.current_file = "trashbeats-melody.mp3"
	_melody_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	_melody_dialog.file_selected.connect(_on_melody_save_selected)
	add_child(_melody_dialog)

	_import_dialog = FileDialog.new()
	_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_import_dialog.filters = PackedStringArray(["*.wav ; WAV 音频"])
	_import_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	_import_dialog.file_selected.connect(_on_melody_import_selected)
	add_child(_import_dialog)

	_melody_tick = Timer.new()
	_melody_tick.wait_time = 0.25
	_melody_tick.one_shot = false
	_melody_tick.timeout.connect(_on_melody_tick)
	add_child(_melody_tick)
	_melody_tick.start()

	_enter_list()

func on_enter() -> void:
	# 点底部"编曲"始终先进列表模式（满足"先进入新建编曲"的要求）
	_enter_list()

func on_exit() -> void:
	_mic_recording = false      # 先置假，避免下方 Audio.stop() 触发的 _on_transport(false) 误存未保存的录制
	Audio.stop()
	if Audio.is_recording():
		Audio.stop_recording()
	if _recorder != null and _recorder.is_recording():
		_recorder.stop_recording()   # 离开页面时丢弃未保存的麦克风录制
	if _recorder != null:
		_recorder.teardown()
		_recorder = null
	Audio.stop_mic()
	_rhythm_sync_pending = false # 离开页面作废挂起的节奏对齐
	Audio.stop_melody()          # 离开编曲页停掉 AI 旋律
	Audio.set_rhythm_volume(1.0) # 恢复节奏音量，防止影响其他页面试听
	Audio.steps = 16   # 恢复默认，防止其他页面预览按 12 步/三连音时值跑

# ── LIST MODE ────────────────────────────────────────────────
func _enter_list() -> void:
	_mode = MODE_LIST
	Audio.stop()
	_build_list()
	_list_container.visible = true
	_edit_container.visible = false

func _build_list() -> void:
	for c in _list_container.get_children():
		c.queue_free()

	_list_container.add_child(UIKit.label("我的编曲", 24, UIKit.COL_NEON, true))

	var projs = GameState.list_projects()
	if projs.is_empty():
		var hint = UIKit.label("还没有编曲，点下面的「＋ 新建编曲」开始", 15, UIKit.COL_MUTED)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_list_container.add_child(hint)
	else:
		var scroll = ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		var list_vb = VBoxContainer.new()
		list_vb.add_theme_constant_override("separation", 10)
		list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list_vb)
		_list_container.add_child(scroll)

		for p in projs:
			list_vb.add_child(_build_project_card(p))

	var new_btn = UIKit.button("＋ 新建编曲", UIKit.COL_NEON, 16)
	new_btn.pressed.connect(_new_project)
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_child(new_btn)

func _build_project_card(p: Dictionary) -> Control:
	var card = UIKit.panel(UIKit.COL_PANEL, UIKit.COL_BORDER, 2, 8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hb = HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	card.add_child(hb)

	var info = VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(UIKit.label(p.name, 18, UIKit.COL_TEXT))
	var meter = "三连音" if p.get("steps", 16) == 12 else "4/4 拍"
	info.add_child(UIKit.label("BPM %d · %d 轨 · %s" % [int(p.bpm), p.tracks.size(), meter], 13, UIKit.COL_MUTED))
	hb.add_child(info)

	var open = UIKit.button("打开", UIKit.COL_NEON, 15)
	open.pressed.connect(func(): _open_project(p.id))
	hb.add_child(open)

	var del = UIKit.button("🗑", UIKit.COL_AI, 15)
	del.pressed.connect(func(): _delete_project(p.id))
	hb.add_child(del)

	return card

func _new_project() -> void:
	# 先选拍号（4/4 或 3/4），选完再创建项目
	_meter_menu.position = get_global_mouse_position()
	_meter_menu.popup()

func _create_project_with_steps(steps_id: int) -> void:
	var n = GameState.list_projects().size() + 1
	var pid = GameState.new_project("编曲 %d" % n, steps_id)
	_open_project(pid)

func _delete_project(id: String) -> void:
	GameState.delete_project(id)
	UIKit.toast(self, "已删除编曲", UIKit.COL_AI)
	_build_list()

# ── EDIT MODE ────────────────────────────────────────────────
func _open_project(pid: String) -> void:
	_current_pid = pid
	var proj = GameState.load_project(pid)
	if proj.is_empty():
		proj = {"id": pid, "name": "未命名编曲", "tracks": [], "patterns": {}, "bpm": 120.0, "steps": 16}
	_tracks = proj.tracks.duplicate()
	_steps = proj.get("steps", 16)   # 老项目无此字段 → 默认 4/4（16 格）
	_div = maxi(1, _steps / 4)       # 每拍格数：16→4，12→3（三连音）
	Audio.steps = _steps             # 引擎在第 _steps 格回头（步长也随 steps 变时值）
	# 载入本项目的"已录制"音频（若有且文件还在）
	var rp = proj.get("recording_path", "")
	if rp != "" and FileAccess.file_exists(rp):
		_recorded_audio = Audio.read_wav(rp)
	else:
		_recorded_audio = PackedFloat32Array()
	_recording_step_count = 0
	# 载入本项目的麦克风录制（若有且文件还在）
	var mp = proj.get("mic_path", "")
	if mp != "" and FileAccess.file_exists(mp):
		_mic_audio = Audio.read_wav(mp)
		_mic_path = mp
	else:
		_mic_audio = PackedFloat32Array()
		_mic_path = ""
	_mic_recording = false
	_mic_step_count = 0
	# 载入本项目的 AI 旋律（若有且文件还在）
	Audio.stop_melody()
	_rhythm_sync_pending = false
	var mel = proj.get("melody_path", "")
	if mel != "" and FileAccess.file_exists(mel):
		_melody_path = mel
		_melody_tags = proj.get("melody_tags", "")
		_downbeat_marks = proj.get("melody_marks", []).duplicate()
	else:
		_melody_path = ""
		_melody_tags = ""
		_downbeat_marks = []
	_mode = MODE_EDIT
	_build_edit_ui(proj)
	_list_container.visible = false
	_edit_container.visible = true
	Audio.stop()

func _build_edit_ui(proj: Dictionary) -> void:
	for c in _edit_container.get_children():
		c.queue_free()
	_cells = []
	_prev_col = -1
	Audio.clear_pattern()   # 切项目时清掉引擎旧 pattern，杜绝跨项目串音

	# ── header / transport ──
	var head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	_edit_container.add_child(head)

	var back = UIKit.button("← 返回", UIKit.COL_NEON, 15)
	back.pressed.connect(_enter_list)
	head.add_child(back)

	_name_edit = LineEdit.new()
	_name_edit.text = proj.name
	_name_edit.placeholder_text = "编曲名称"
	_name_edit.add_theme_font_override("font", UIKit.cjk_font())
	_name_edit.add_theme_font_size_override("font_size", 15)
	_name_edit.add_theme_color_override("font_color", UIKit.COL_TEXT)
	_name_edit.add_theme_stylebox_override("normal", UIKit.style_box(UIKit.COL_PANEL, UIKit.COL_BORDER, 1, 4))
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t): GameState.rename_project(_current_pid, _name_edit.text))
	_name_edit.focus_exited.connect(func(): GameState.rename_project(_current_pid, _name_edit.text))
	head.add_child(_name_edit)

	var bpm_minus = UIKit.button("−", UIKit.COL_NEON, 18)
	bpm_minus.custom_minimum_size = Vector2(40, 0)
	bpm_minus.pressed.connect(func(): _set_bpm(Audio.bpm - 1))
	head.add_child(bpm_minus)
	var bpm_cap = UIKit.label("BPM", 16, UIKit.COL_NEON, true)
	bpm_cap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(bpm_cap)
	_bpm_edit = LineEdit.new()
	_bpm_edit.text = _fmt_bpm(Audio.bpm)
	_bpm_edit.placeholder_text = "BPM"
	_bpm_edit.add_theme_font_override("font", UIKit.pixel_font())
	_bpm_edit.add_theme_font_size_override("font_size", 16)
	_bpm_edit.add_theme_color_override("font_color", UIKit.COL_NEON)
	_bpm_edit.add_theme_stylebox_override("normal", UIKit.style_box(UIKit.COL_PANEL, UIKit.COL_BORDER, 1, 4))
	_bpm_edit.custom_minimum_size = Vector2(72, 0)
	_bpm_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bpm_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bpm_edit.max_length = 6
	_bpm_edit.text_submitted.connect(func(_t): _apply_bpm_edit())
	_bpm_edit.focus_exited.connect(func(): _apply_bpm_edit())
	head.add_child(_bpm_edit)
	var bpm_plus = UIKit.button("+", UIKit.COL_NEON, 18)
	bpm_plus.custom_minimum_size = Vector2(40, 0)
	bpm_plus.pressed.connect(func(): _set_bpm(Audio.bpm + 1))
	head.add_child(bpm_plus)

	_play_btn = UIKit.button("▶ 播放", UIKit.COL_NEON, 16)
	_play_btn.pressed.connect(_toggle_transport)
	head.add_child(_play_btn)

	var clear_btn = UIKit.button("清空", UIKit.COL_NEON, 16)
	clear_btn.pressed.connect(_clear_all)
	head.add_child(clear_btn)

	var ai_btn = UIKit.button("✦ 智能续写", UIKit.COL_AI, 16)
	ai_btn.pressed.connect(_ai_continue)
	head.add_child(ai_btn)

	var ai_undo_btn = UIKit.button("↶ 取消智能续写", UIKit.COL_AI, 16)
	ai_undo_btn.pressed.connect(_undo_ai_continue)
	ai_undo_btn.visible = false
	head.add_child(ai_undo_btn)
	_ai_undo_btn = ai_undo_btn
	_ai_snapshot = []   # 进入编曲即清空旧快照，避免跨项目误恢复

	var add_btn = UIKit.button("＋ 添加轨道", UIKit.COL_NEON, 16)
	add_btn.pressed.connect(_open_add_menu)
	head.add_child(add_btn)

	_rec_btn = UIKit.button("● 录制", UIKit.COL_AI, 16)
	_rec_btn.pressed.connect(_toggle_recording)
	head.add_child(_rec_btn)

	var melody_btn = UIKit.button("🎵 生成旋律", UIKit.COL_AI, 16)
	melody_btn.pressed.connect(_request_melody)
	head.add_child(melody_btn)

	_status_label = UIKit.label("BPM 120 ● PAUSED", 13, UIKit.COL_MUTED, true)
	_edit_container.add_child(_status_label)

	# ── 三区域纵向分割：节奏 / 旋律 / 麦克风（每区独立滚轮 + 连接处可拖拽）──
	var split_outer = VSplitContainer.new()
	split_outer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_outer.add_theme_constant_override("separation", 4)

	# 区域1：节奏（格子 + 提示 + 已录制轨），默认占 2/3
	var rhythm_scroll = ScrollContainer.new()
	rhythm_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rhythm_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rhythm_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rhythm_scroll.size_flags_stretch_ratio = 2.0
	var rhythm_vb = VBoxContainer.new()
	rhythm_vb.add_theme_constant_override("separation", 10)
	rhythm_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rhythm_scroll.add_child(rhythm_vb)
	_rhythm_vb = rhythm_vb

	var split_inner = VSplitContainer.new()
	split_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_inner.size_flags_stretch_ratio = 1.0
	split_inner.add_theme_constant_override("separation", 4)

	# 区域2：旋律
	var melody_scroll = ScrollContainer.new()
	melody_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	melody_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	melody_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	melody_scroll.size_flags_stretch_ratio = 1.0
	var melody_vb = VBoxContainer.new()
	melody_vb.add_theme_constant_override("separation", 8)
	melody_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	melody_scroll.add_child(melody_vb)

	# 区域3：麦克风
	var mic_scroll = ScrollContainer.new()
	mic_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	mic_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mic_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mic_scroll.size_flags_stretch_ratio = 1.0
	var mic_vb = VBoxContainer.new()
	mic_vb.add_theme_constant_override("separation", 8)
	mic_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mic_scroll.add_child(mic_vb)
	_mic_vb = mic_vb

	# ── grid（节奏区的轨道行，直接进 rhythm_vb，不再套一层 ScrollContainer）──
	var grid_vb = rhythm_vb

	Audio.bpm = proj.bpm
	_bpm_edit.text = _fmt_bpm(Audio.bpm)

	for r in _tracks.size():
		var id: String = _tracks[r]
		var inst: Dictionary = GameState.get_instrument(id)
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		var name_lbl = UIKit.label(inst.get("name", id), 13, inst.get("color", UIKit.COL_TEXT))
		name_lbl.custom_minimum_size = Vector2(170, 0)
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(name_lbl)

		var gtrack = GameState.global_track_of(id)
		var track_cells = []
		for s in _steps:
			if s > 0 and s % _div == 0:
				var sep = Control.new()
				sep.custom_minimum_size = Vector2(8, 0)
				row.add_child(sep)
			var cell = SeqCell.new(gtrack, s, inst.get("color", Color.WHITE))
			cell.div = _div
			cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cell.size_flags_vertical = Control.SIZE_EXPAND_FILL
			cell.changed.connect(_on_cell_changed)
			row.add_child(cell)
			track_cells.append(cell)
		# 行尾删除按钮（预设 / 自定义轨都可删）
		var rr = r
		var del_btn = UIKit.button("🗑", UIKit.COL_AI, 14)
		del_btn.custom_minimum_size = Vector2(36, 36)
		del_btn.pressed.connect(func(): _delete_track(rr))
		row.add_child(del_btn)

		_cells.append(track_cells)
		grid_vb.add_child(row)

	# ── footer hints（进节奏区）──
	var foot = HBoxContainer.new()
	foot.add_theme_constant_override("separation", 28)
	foot.add_child(UIKit.label("● 点格子 放音符", 13, UIKit.COL_MUTED))
	foot.add_child(UIKit.label("● 按住上下拖 调音高", 13, UIKit.COL_MUTED))
	foot.add_child(UIKit.label("● 右键 删除", 13, UIKit.COL_MUTED))
	foot.add_child(UIKit.label("● AI 模式:点 2~4 个音当种子 → 续写", 13, UIKit.COL_MUTED))
	foot.add_child(UIKit.label("● ＋添加轨道 从乐器库选声音 · 🗑 删轨", 13, UIKit.COL_MUTED))
	rhythm_vb.add_child(foot)

	# ── AI 旋律区块（生成表单 + 播放器）→ 旋律区 ──
	_melody_holder = VBoxContainer.new()
	_melody_holder.add_theme_constant_override("separation", 8)
	melody_vb.add_child(_melody_holder)
	_build_melody_block()
	if _melody_path != "" and _downbeat_marks.is_empty():
		_auto_align_melody(false)

	# ── 已录制区块（仅当本项目有录音时显示）→ 节奏区，格子下方 ──
	_build_rec_block(_rhythm_vb)

	# ── 麦克风录制区块（常驻，可随时录制/回放/导出）→ 麦克风区 ──
	_build_mic_block(_mic_vb)

	# ── 组装三层纵向分割 ──
	split_inner.add_child(melody_scroll)
	split_inner.add_child(mic_scroll)
	split_outer.add_child(rhythm_scroll)
	split_outer.add_child(split_inner)
	_edit_container.add_child(split_outer)

	# ── load patterns from project (keyed by instrument id) ──
	var pats: Dictionary = proj.patterns
	for r in _tracks.size():
		var id: String = _tracks[r]
		var arr = pats.get(id, [])
		for s in _steps:
			var entry = arr[s] if s < arr.size() else null
			if entry is Dictionary and entry.get("on", false):
				_cells[r][s].set_note(true, entry.get("ai", false), entry.get("pitch", 0))
				_sync_cell(_cells[r][s], false)
			else:
				_cells[r][s].set_note(false)
				_sync_cell(_cells[r][s], false)

	_on_transport(Audio.playing)

# ── save / load (project model) ─────────────────────────────
func _save_current_patterns() -> void:
	if _current_pid == "" or _mode != MODE_EDIT:
		return
	var pats = {}
	for r in _tracks.size():
		var id: String = _tracks[r]
		var arr = []
		if r < _cells.size():
			for s in _steps:
				var c: SeqCell = _cells[r][s]
				if c.on:
					arr.append({"on": true, "pitch": c.pitch, "ai": c.ai})
				else:
					arr.append(null)
		pats[id] = arr
	GameState.save_project(_current_pid, _tracks, pats, Audio.bpm, _recorded_audio if _recorded_audio.size() > 0 else null)

func _on_cell_changed(cell: SeqCell) -> void:
	_sync_cell(cell, true)
	_save_current_patterns()

func _sync_cell(cell: SeqCell, audition: bool) -> void:
	if cell.on:
		Audio.set_cell(cell.track, cell.step, {
			"pitch": cell.pitch,
			"vel": 1.0 if cell.step % _div == 0 else 0.85,
		})
		if audition and not Audio.playing:
			Audio.trigger(cell.track, cell.pitch)
	else:
		Audio.set_cell(cell.track, cell.step, null)

func _set_bpm(v: float) -> void:
	Audio.bpm = clampf(v, 20.0, 400.0)
	if _bpm_edit != null and is_instance_valid(_bpm_edit):
		_bpm_edit.text = _fmt_bpm(Audio.bpm)
	_save_current_patterns()
	_on_transport(Audio.playing)

## 从 BPM 输入框读取并应用（回车 / 失焦触发）。
func _apply_bpm_edit() -> void:
	if _bpm_edit == null or not is_instance_valid(_bpm_edit):
		return
	var t = _bpm_edit.text.strip_edges()
	if t == "":
		_bpm_edit.text = _fmt_bpm(Audio.bpm)
		return
	var v = float(t)
	if v <= 0.0 or v != v:  # NaN 检查
		UIKit.toast(self, "BPM 需为大于 0 的数字", UIKit.COL_AI)
		_bpm_edit.text = _fmt_bpm(Audio.bpm)
		return
	_set_bpm(v)

func _toggle_transport() -> void:
	if Audio.playing or _rhythm_sync_pending:
		# 停止：节奏停了；同步模式下连带停旋律 + 取消挂起的对齐
		_rhythm_sync_pending = false
		if Audio.playing:
			Audio.stop()
		if Audio.is_recording():
			_finish_recording()
		if _downbeat_marks.size() > 0:
			Audio.stop_melody()
		if _play_btn != null:
			_play_btn.text = "▶ 播放"
		if _status_label != null:
			_status_label.text = "BPM " + _fmt_bpm(Audio.bpm) + " ● PAUSED"
	else:
		# 已有旋律且标了强拍 → 旋律从头起播,节奏挂起到第一个强拍再进(对齐)
		if _melody_path != "" and _downbeat_marks.size() > 0:
			_sync_anchor = float(_downbeat_marks[0])
			if Audio.play_melody(_melody_path):
				_rhythm_sync_pending = true
				if _play_btn != null:
					_play_btn.text = "⏳ 对齐中…"
				UIKit.toast(self, "旋律起播，节奏将在第一个强拍进入", UIKit.COL_NEON)
			else:
				UIKit.toast(self, "旋律文件读取失败，仅播节奏", UIKit.COL_AI)
				Audio.start()
		else:
			Audio.start()

func _process(_delta: float) -> void:
	if _recorder != null:
		_recorder.process()   # 每帧把麦克风捕获缓冲抽出来（未录制时为空操作）
	if not _rhythm_sync_pending:
		return
	if Audio.is_melody_playing():
		# 等旋律播放位置越过第一个强拍锚点 → 起节奏(step0 对齐强拍)
		if Audio.melody_position() >= _sync_anchor:
			_rhythm_sync_pending = false
			Audio.start()
	else:
		# 旋律已结束/未起播（如锚点超过旋律末尾）→ 兜底直接起节奏,避免卡死
		_rhythm_sync_pending = false
		Audio.start()

func _on_transport(playing: bool) -> void:
	if not playing:
		_rhythm_sync_pending = false   # 鼓点停了,挂起的对齐作废
		Audio.stop_mic()               # 停止时一并停掉麦克风回放
		if _mic_recording:
			_finish_mic_recording()    # 停播放=结束本次麦克风录制并保存
	if _mode != MODE_EDIT or _play_btn == null:
		return
	_play_btn.text = "■ 停止" if playing else "▶ 播放"
	_status_label.text = "BPM " + _fmt_bpm(Audio.bpm) + " ● " + ("PLAYING" if playing else "PAUSED")
	# 随歌曲一起播麦克风片段（正在录麦克风 / 正在录混音时不触发，避免回授或重迭）
	if playing and _mic_audio.size() > 0 and not _mic_recording and not Audio.is_recording():
		Audio.play_mic(_mic_audio)
	if not playing and _prev_col >= 0:
		_set_column_playing(_prev_col, false)
		_prev_col = -1

func _on_step(step: int) -> void:
	if _mode != MODE_EDIT:
		return
	if Audio.is_recording():
		_recording_step_count += 1
		if _recording_step_count >= REC_LOOP_LIMIT * _steps:
			UIKit.toast(self, "已录满 %d 个循环，自动停止" % REC_LOOP_LIMIT, UIKit.COL_NEON)
			_finish_recording()
			return
	if _mic_recording:
		_mic_step_count += 1
		if _mic_step_count >= REC_LOOP_LIMIT * _steps:
			UIKit.toast(self, "已录满 %d 个循环，麦克风自动停止" % REC_LOOP_LIMIT, UIKit.COL_NEON)
			_finish_mic_recording()
			return
	if _prev_col >= 0 and _prev_col != step:
		_set_column_playing(_prev_col, false)
	_set_column_playing(step, true)
	_prev_col = step
	for t in _tracks.size():
		var cell: SeqCell = _cells[t][step]
		if cell.on:
			cell.pulse()

func _set_column_playing(step: int, v: bool) -> void:
	for t in _tracks.size():
		_cells[t][step].playing_col = v
		_cells[t][step].queue_redraw()

func _clear_all() -> void:
	Audio.clear_pattern()
	for t in _tracks.size():
		for s in _steps:
			_cells[t][s].set_note(false)
	_save_current_patterns()
	UIKit.toast(self, "已清空画布", UIKit.COL_NEON)

# ── 添加 / 删除轨道 ─────────────────────────────────────────
# 与乐器库（收藏）联通：可选声音来自 favorite_instruments()。
# 新增的轨道 = 把该乐器 id 追加进当前项目的 _tracks（发声走 global_track_of，
# 与乐器库试听同套，自定义录音轨也能直接接）。

func _open_add_menu() -> void:
	if _add_menu == null:
		return
	_addable_ids = []
	_add_menu.clear()
	for inst in GameState.favorite_instruments():
		var id: String = inst.get("id", "")
		if id == "" or _tracks.has(id):
			continue
		var gt = GameState.global_track_of(id)
		if gt < 0 or gt >= Audio.TRACKS:
			continue
		var tag = " · 已处理" if inst.get("custom", false) else ""
		_add_menu.add_item("%s%s" % [inst.get("name", id), tag])
		_addable_ids.append(id)
	if _addable_ids.is_empty():
		UIKit.toast(self, "乐器库里的声音都已加入，或音轨已满", UIKit.COL_NEON)
		return
	_add_menu.position = get_global_mouse_position()
	_add_menu.popup()

func _on_add_track_selected(idx: int) -> void:
	if idx < 0 or idx >= _addable_ids.size():
		return
	_add_track(_addable_ids[idx])

func _add_track(id: String) -> void:
	if _tracks.has(id):
		return
	var gt = GameState.global_track_of(id)
	if gt < 0 or gt >= Audio.TRACKS:
		UIKit.toast(self, "音轨已满（最多 %d 条）" % Audio.TRACKS, UIKit.COL_AI)
		return
	_tracks.append(id)
	_save_current_patterns()        # 新加 id 行：_cells 尚无 -> 守卫成全空
	_open_project(_current_pid)     # 重建，新行出现（空）
	UIKit.toast(self, "已添加轨道：%s" % GameState.get_instrument(id).get("name", id), UIKit.COL_NEON)

func _delete_track(r: int) -> void:
	if r < 0 or r >= _tracks.size():
		return
	var removed_id: String = _tracks[r]
	var gt = GameState.global_track_of(removed_id)
	if gt >= 0:
		for s in STEPS:
			Audio.set_cell(gt, s, null)   # 清掉引擎里该轨的 pattern
	_tracks.remove_at(r)
	if r < _cells.size():
		_cells.remove_at(r)
	_save_current_patterns()
	_open_project(_current_pid)      # 重建，行消失且存盘生效
	UIKit.toast(self, "已删除轨道", UIKit.COL_NEON)

# ── 智能续写 ─────────────────────────────────────────────────
# Musically-informed algorithmic continuation. Analyzes user seed notes
# across all tracks, then generates complementary rhythms with melodic
# arcs. No ML — but produces convincing demo output.
# Generated cells are flagged ai=true and rendered with COL_AI.

# Minor pentatonic: semitone offsets from root
const PENTATONIC = [0, 3, 5, 7, 10]

func _user_seed_steps(t: int) -> Array:
	var out = []
	for s in _steps:
		var c: SeqCell = _cells[t][s]
		if c.on and not c.ai:
			out.append(s)
	return out

func _analyze_seeds() -> Dictionary:
	var n = _tracks.size()
	var ctx = {
		"total": 0,
		"track_seeds": [],
		"seed_steps": [],
		"pitch_center": [],
		"quarter_density": [0.0, 0.0, 0.0, 0.0],  # 每拍密度（4 拍/循环，按 _div 分桶）
		"first_phrase_seeds": 0,   # steps 0-7
		"second_phrase_seeds": 0,  # steps 8-15
	}
	for i in n:
		ctx.track_seeds.append(0)
		ctx.seed_steps.append([])
		ctx.pitch_center.append(0)
	for t in n:
		var steps = _user_seed_steps(t)
		ctx.seed_steps[t] = steps
		ctx.track_seeds[t] = steps.size()
		ctx.total += steps.size()
		for s in steps:
			ctx.quarter_density[s / _div] += 1.0
			if s < _steps / 2:
				ctx.first_phrase_seeds += 1
			else:
				ctx.second_phrase_seeds += 1
		# pitch center per track (melodic tracks only)
		if t >= 2 and steps.size() > 0:
			var sum = 0.0
			for s in steps:
				sum += float(_cells[t][s].pitch)
			ctx.pitch_center[t] = int(round(sum / steps.size()))
	return ctx

# Rhythm generation (rules-only): anchor phrase boundaries first, then strong /
# syncopated positions, then generic fills. Uses per-beat user density
# (quarter_density) for voice complementarity and skips steps already claimed by
# the melodic tracks (occupied) so drums don't collide with the melody.
func _gen_rhythm(track: int, target_density: int, ctx: Dictionary, occupied: Variant = null) -> Array:
	if occupied == null:
		occupied = []
	var user: Array = ctx.seed_steps[track]
	var strong = []
	var offbeat = []
	for b in range(0, _steps, _div):
		strong.append(b)
		offbeat.append(b + (1 if _div == 3 else 2))
	var phrase_end = [_steps / 2 - 1, _steps - 1]

	var chosen = []
	# 1) always anchor phrase boundaries if the user left them empty
	for b in phrase_end:
		if not user.has(b) and not occupied.has(b):
			chosen.append(b)

	# 2) candidate pool with a preference weight (high = rhythmic anchor)
	var pool = []
	if track <= 1:
		for b in strong:
			if not user.has(b) and not occupied.has(b):
				pool.append({"s": b, "pref": 2})
		if track == 1 or track == 2:
			for b in offbeat:
				if not user.has(b) and not occupied.has(b):
					pool.append({"s": b, "pref": 1})
	if track == 3:
		for b in [_steps - _div, _steps - _div + (1 if _div == 3 else 2)]:
			if not user.has(b) and not occupied.has(b):
				pool.append({"s": b, "pref": 1})
	for s in range(_steps):
		if not user.has(s) and not occupied.has(s):
			pool.append({"s": s, "pref": 0})

	# 3) sort: anchors first; within the same weight, prefer beats the user left
	#    sparse (voice complementarity — AI fills where the user didn't).
	#    Manual insertion sort to avoid sort_custom + Callable parser issues.
	for i in range(1, pool.size()):
		var key = pool[i]
		var j = i - 1
		while j >= 0:
			var pj = pool[j]
			var swap = false
			if key.pref > pj.pref:
				swap = true
			elif key.pref == pj.pref:
				var dk = ctx.quarter_density[int(key.s / _div)]
				var dj = ctx.quarter_density[int(pj.s / _div)]
				if dk < dj:
					swap = true
			if swap:
				pool[j + 1] = pool[j]
				j -= 1
			else:
				break
		pool[j + 1] = key

	for p in pool:
		if chosen.has(p.s):
			continue
		chosen.append(p.s)
		if chosen.size() >= target_density:
			break

	chosen.sort()
	return chosen.slice(0, target_density)

# Build a melodic line with a directed random walk over the pentatonic scale
# (motivic, not a fixed arc). Track 3 is a parallel harmony voice: it shadows
# track 2 a third/sixth below instead of repeating the same shape.
func _gen_pitches(track: int, steps: Array, ctx: Dictionary, harmony_ref: Variant = null) -> Array:
	if harmony_ref == null:
		harmony_ref = {}
	var out = []
	var n = steps.size()
	if n == 0:
		return out
	var center: int = ctx.pitch_center[track]
	var sc = _build_scale(center)
	if sc.is_empty():
		sc = [clampi(center, -6, 6)]
	var cur: int = int(sc.size() * 0.5)        # start near the centre (= seed pitch)
	var drift: int = 1 if (randi() % 2 == 0) else -1
	for i in n:
		# occasional reversal -> phrase-like direction changes
		if i > 0 and randf() < 0.22:
			drift = -drift
		var jump: int = 2 if (randf() < 0.15) else 1   # occasional leap
		cur = clampi(cur + drift * jump, 0, sc.size() - 1)
		var semi: int = sc[cur]
		if track == 3 and harmony_ref.has(steps[i]):
			# parallel third/sixth below the lead voice
			semi = _nearest_in_scale(sc, harmony_ref[steps[i]] - 4)
		out.append(semi)
	return out

## Pentatonic scale steps available around `center`, clamped to the UI pitch range [-6, 6].
func _build_scale(center: int) -> Array:
	var sc = []
	for octv in [-1, 0, 1]:
		for p in PENTATONIC:
			var semi = center + p + octv * 12
			if semi >= -6 and semi <= 6:
				sc.append(semi)
	sc.sort()
	return sc

func _nearest_in_scale(sc: Array, target: int) -> int:
	if sc.is_empty():
		return clampi(target, -6, 6)
	var best: int = sc[0]
	var bd: int = 999
	for s in sc:
		var d: int = absi(s - target)
		if d < bd:
			bd = d
			best = s
	return best

## Snap a semitone to the nearest minor-pentatonic pitch, clamped to [-6, 6].
func _snap_pentatonic(semi: int) -> int:
	var best: int = semi
	var best_d: int = 999
	for p in PENTATONIC:
		for oct in [-12, 0, 12]:
			var candidate: int = p + oct
			var d: int = absi(candidate - semi)
			if d < best_d:
				best_d = d
				best = candidate
	return clampi(best, -6, 6)

# Expressive velocity: a phrase-wide breathing envelope (soft opening -> louder
# middle -> tapering end) plus a per-hit humanize jitter, so the AI line feels
# played rather than mechanical. Strong beats get a small lift.
func _ai_velocity(step: int) -> float:
	var phrase_len: float = float(_steps) / 2.0
	var pos: float = fmod(float(step), phrase_len) / phrase_len   # 0.0 → 1.0
	var breath: float = 0.80 + 0.20 * sin(pos * PI)               # 0.80 → 1.0 → 0.80
	var beat_boost: float = 0.0
	if step % _div == 0:
		beat_boost = 0.08
	var humanize: float = (randf() - 0.5) * 0.10                   # ±0.05
	var v: float = breath + beat_boost + humanize
	return clampf(v, 0.45, 1.0)

func _ai_continue() -> void:
	var ctx = _analyze_seeds()
	if ctx.total == 0:
		UIKit.toast(self, "先点 2~4 个音当种子,AI 才知道往哪写", UIKit.COL_NEON)
		return

	# Snapshot the pre-continuation state (hand-written seeds + any prior AI)
	# so the user can revert with the «取消智能续写» button.
	_take_ai_snapshot()

	# Wipe previous AI notes
	for t in _tracks.size():
		for s in _steps:
			var c: SeqCell = _cells[t][s]
			if c.on and c.ai:
				c.set_note(false)
				_sync_cell(c, false)

	# Density targets per track; presets get musical roles, extra tracks get a
	# sensible generic fill (Phase 3 will refine custom-track handling).
	var densities = []
	for t in _tracks.size():
		if t == 0:
			densities.append(clampi(ctx.track_seeds[0] + 3, 4, 8))   # kick: steady pulse
		elif t == 1:
			densities.append(clampi(ctx.track_seeds[1] + 2, 3, 7))   # woodblock: lighter
		elif t == 2:
			densities.append(clampi(ctx.track_seeds[2] + 2, 3, 6))   # bell: melodic
		elif t == 3:
			densities.append(clampi(ctx.track_seeds[3] + 1, 2, 4))   # tom: sparse fills
		else:
			densities.append(clampi(ctx.track_seeds[t] + 1, 2, 5))   # extra tracks

	# Pass 1 — melodic tracks (t >= 2). Remember which steps they occupy so the
	# drum tracks can avoid colliding with the melody.
	var occupied = []
	var melody_map = {}
	for t in _tracks.size():
		if t < 2:
			continue
		var steps = _gen_rhythm(t, densities[t], ctx, occupied)
		var pitches = _gen_pitches(t, steps, ctx, melody_map if (t == 3) else {})
		if t == 2:
			for i in steps.size():
				melody_map[steps[i]] = pitches[i]
		for i in steps.size():
			var s: int = steps[i]
			if _cells[t][s].on:
				continue
			var p: int = pitches[i] if i < pitches.size() else 0
			_cells[t][s].set_note(true, true, p)
			Audio.set_cell(_cells[t][s].track, s, {"pitch": p, "vel": _ai_velocity(s)})
		occupied.append_array(steps)

	# Pass 2 — drum tracks (t < 2). Skip steps the melody already claims.
	for t in _tracks.size():
		if t >= 2:
			continue
		var steps = _gen_rhythm(t, densities[t], ctx, occupied)
		for i in steps.size():
			var s: int = steps[i]
			if _cells[t][s].on:
				continue
			_cells[t][s].set_note(true, true, 0)
			Audio.set_cell(_cells[t][s].track, s, {"pitch": 0, "vel": _ai_velocity(s)})

	_save_current_patterns()
	if _ai_undo_btn != null and is_instance_valid(_ai_undo_btn):
		_ai_undo_btn.visible = true
	UIKit.toast(self, "智能续写已生成 · 紫色格子可拖、可删、可改 · 不满意可 ↶ 撤销", UIKit.COL_AI)

## Capture the full grid (on/ai/pitch per cell) for undo.
func _take_ai_snapshot() -> void:
	_ai_snapshot = []
	for r in _cells.size():
		var row = []
		for s in _steps:
			var c: SeqCell = _cells[r][s]
			row.append({"on": c.on, "ai": c.ai, "pitch": c.pitch})
		_ai_snapshot.append(row)

## Restore the pre-continuation grid and hide the undo button.
func _undo_ai_continue() -> void:
	if _ai_snapshot.size() == 0:
		UIKit.toast(self, "没有可撤销的智能续写", UIKit.COL_AI)
		return
	for r in _ai_snapshot.size():
		for s in _steps:
			var snap: Dictionary = _ai_snapshot[r][s]
			var c: SeqCell = _cells[r][s]
			c.set_note(snap.on, snap.ai, snap.pitch)
			_sync_cell(c, false)
	_ai_snapshot = []
	if _ai_undo_btn != null and is_instance_valid(_ai_undo_btn):
		_ai_undo_btn.visible = false
	_save_current_patterns()
	UIKit.toast(self, "已撤销智能续写，回到手工状态", UIKit.COL_NEON)

# ── 已录制区块（Phase 4）────────────────────────────────
func _build_rec_block(parent: Control) -> void:
	for c in parent.get_children():
		if is_instance_valid(c) and c.has_meta("rec_block") and c.get_meta("rec_block"):
			c.queue_free()
	if _recorded_audio.size() == 0:
		return
	var block = HBoxContainer.new()
	block.set_meta("rec_block", true)
	block.add_theme_constant_override("separation", 12)
	var dur = _recorded_audio.size() / float(Audio.MIX_RATE)
	var label = UIKit.label("🎙 已录制 · %.1fs" % dur, 14, UIKit.COL_AI)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	block.add_child(label)
	var play = UIKit.button("▶ 播放", UIKit.COL_NEON, 15)
	play.pressed.connect(_play_recording)
	block.add_child(play)
	var save = UIKit.button("💾 保存", UIKit.COL_NEON, 15)
	save.pressed.connect(func(): _rec_dialog.popup())
	block.add_child(save)
	var del = UIKit.button("🗑", UIKit.COL_AI, 15)
	del.pressed.connect(_delete_recording)
	block.add_child(del)
	parent.add_child(block)

func _toggle_recording() -> void:
	if Audio.is_recording():
		_finish_recording()
	else:
		_recording_step_count = 0
		Audio.start_recording()
		if not Audio.playing:
			Audio.start()
		_update_rec_btn()
		UIKit.toast(self, "录制中…可随时改格子，点 ■ 停止 结束", UIKit.COL_AI)

func _finish_recording() -> void:
	var buf = Audio.stop_recording()
	_update_rec_btn()
	if buf.size() == 0:
		UIKit.toast(self, "没录到声音", UIKit.COL_AI)
		return
	# Apply noise suppression to the recorded mix output
	buf = _denoise_recording(buf)
	_recorded_audio = buf
	_save_current_patterns()   # 顺带把录音存进当前项目
	_build_rec_block(_rhythm_vb)
	var dur = buf.size() / float(Audio.MIX_RATE)
	UIKit.toast(self, "已录制 %.1fs，已存入本项目" % dur, UIKit.COL_NEON)

func _update_rec_btn() -> void:
	if _rec_btn == null:
		return
	if Audio.is_recording():
		_rec_btn.text = "■ 停止"
	else:
		_rec_btn.text = "● 录制"

func _play_recording() -> void:
	Audio.play_one_shot(_recorded_audio)

func _delete_recording() -> void:
	_recorded_audio = PackedFloat32Array()
	GameState.remove_recording(_current_pid)
	_build_rec_block(_rhythm_vb)
	UIKit.toast(self, "已删除录制", UIKit.COL_AI)

func _on_rec_save_selected(path: String) -> void:
	if _recorded_audio.size() == 0:
		return
	if Audio.write_wav(path, _recorded_audio):
		UIKit.toast(self, "已导出 WAV：%s" % path, UIKit.COL_NEON)
	else:
		UIKit.toast(self, "导出失败，检查路径权限", UIKit.COL_AI)

# ── 麦克风录制轨（Stage A）────────────────────────────
# 常驻区块：始终显示「● 录制」按钮；有片段时追加 时长/播放/导出/删除。
func _build_mic_block(parent: Control) -> void:
	for c in parent.get_children():
		if is_instance_valid(c) and c.has_meta("mic_block") and c.get_meta("mic_block"):
			c.queue_free()
	var block = HBoxContainer.new()
	block.set_meta("mic_block", true)
	block.add_theme_constant_override("separation", 12)
	var label = UIKit.label("🎤 麦克风", 14, UIKit.COL_AI)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	block.add_child(label)
	var rec = UIKit.button("● 录制", UIKit.COL_AI, 15)
	rec.pressed.connect(_toggle_mic_recording)
	block.add_child(rec)
	_mic_rec_btn = rec
	if _mic_audio.size() > 0:
		var dur = _mic_audio.size() / float(Audio.MIX_RATE)
		var dur_lbl = UIKit.label("· %.1fs" % dur, 13, UIKit.COL_MUTED)
		dur_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		block.add_child(dur_lbl)
		var play = UIKit.button("▶ 播放", UIKit.COL_NEON, 15)
		play.pressed.connect(_play_mic)
		block.add_child(play)
		var save = UIKit.button("💾 导出", UIKit.COL_NEON, 15)
		save.pressed.connect(_open_mic_export_dialog)
		block.add_child(save)
		var del = UIKit.button("🗑", UIKit.COL_AI, 15)
		del.pressed.connect(_delete_mic)
		block.add_child(del)
	if _mic_recording:
		_mic_rec_btn.text = "■ 停止"
	parent.add_child(block)

func _toggle_mic_recording() -> void:
	if Recorder.is_capture_supported() and not _mic_recording:
		if _recorder == null:
			_recorder = Recorder.new()
		if not _recorder.available():
			_recorder.setup(self)
	if _recorder == null or not _recorder.available():
		UIKit.toast(self, "当前环境不支持麦克风录音（请确认系统已授权麦克风，且非 Web 导出）", UIKit.COL_AI)
		return
	if _mic_recording:
		_finish_mic_recording()
	else:
		_mic_step_count = 0
		_recorder.start_recording()
		_mic_recording = true
		if not Audio.playing:
			Audio.start()   # 自动起播伴奏，方便跟着即兴
		_update_mic_rec_btn()
		UIKit.toast(self, "🎤 录制中…跟着鼓声即兴，点 ■ 停止 结束", UIKit.COL_AI)

func _finish_mic_recording() -> void:
	if _recorder == null:
		_mic_recording = false
		return
	var buf = _recorder.stop_recording()
	_recorder.teardown()
	_mic_recording = false
	_update_mic_rec_btn()
	if buf.size() == 0:
		UIKit.toast(self, "没录到声音", UIKit.COL_AI)
		return
	buf = _denoise_recording(buf)   # 复用现有降噪
	_mic_audio = buf
	_mic_path = "user://projects/%s_mic.wav" % _current_pid
	Audio.write_wav(_mic_path, _mic_audio)
	GameState.save_mic(_current_pid, _mic_path)
	_build_mic_block(_mic_vb)
	var dur = buf.size() / float(Audio.MIX_RATE)
	UIKit.toast(self, "已录麦克风 %.1fs，已存入本项目" % dur, UIKit.COL_NEON)

func _update_mic_rec_btn() -> void:
	if _mic_rec_btn == null:
		return
	_mic_rec_btn.text = "■ 停止" if _mic_recording else "● 录制"

func _play_mic() -> void:
	Audio.play_mic(_mic_audio)

func _open_mic_export_dialog() -> void:
	_mic_dialog.popup()

func _delete_mic() -> void:
	_mic_audio = PackedFloat32Array()
	_mic_path = ""
	Audio.stop_mic()
	GameState.remove_mic(_current_pid)
	_build_mic_block(_mic_vb)
	UIKit.toast(self, "已删除麦克风录音", UIKit.COL_AI)

func _on_mic_save_selected(path: String) -> void:
	if _mic_audio.size() == 0:
		return
	if Audio.write_wav(path, _mic_audio):
		UIKit.toast(self, "已导出麦克风 WAV：%s" % path, UIKit.COL_NEON)
	else:
		UIKit.toast(self, "导出失败，检查路径权限", UIKit.COL_AI)

# ── AI 旋律生成（阶段 5）────────────────────────────────
# 调用天琴工作流 API：BPM（当前编曲页）+ 用户风格描述 → 生成一段旋律 MP3。
# 旋律走独立播放器，不进混音管线，所以「录制」抓到的仍只有节奏（与用户确认的设计）。
# 用户可 💾 下载 MP3，拿去 Logic Pro 等软件和导出的节奏 WAV 混合。

func _styled_line_edit(placeholder: String) -> LineEdit:
	var le = LineEdit.new()
	le.placeholder_text = placeholder
	le.add_theme_font_override("font", UIKit.cjk_font())
	le.add_theme_font_size_override("font_size", 14)
	le.add_theme_color_override("font_color", UIKit.COL_TEXT)
	le.add_theme_color_override("font_placeholder_color", UIKit.COL_MUTED)
	le.add_theme_stylebox_override("normal", UIKit.style_box(UIKit.COL_PANEL, UIKit.COL_BORDER, 1, 4))
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return le

func _build_melody_block() -> void:
	if _melody_holder == null:
		return
	# 重建前保留用户已填的文字
	var keep_style = ""
	var keep_lyrics = ""
	if _style_edit != null and is_instance_valid(_style_edit):
		keep_style = _style_edit.text
	if _lyrics_edit != null and is_instance_valid(_lyrics_edit):
		keep_lyrics = _lyrics_edit.text
	for c in _melody_holder.get_children():
		c.queue_free()
	_melody_wave = null
	_melody_bpm_label = null
	_step_labels = []
	_melody_bpm_applied = false

	var panel = UIKit.panel(UIKit.COL_PANEL, UIKit.COL_BORDER, 2, 8)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vb = VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)
	_melody_holder.add_child(panel)

	# ── 生成表单 ──
	var form = HBoxContainer.new()
	form.add_theme_constant_override("separation", 10)
	var title = UIKit.label("🎵 AI 旋律", 14, UIKit.COL_AI)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.custom_minimum_size = Vector2(90, 0)
	form.add_child(title)

	_style_edit = _styled_line_edit("风格（如：电子 律动 器乐 / upbeat electronic）")
	_style_edit.text = keep_style
	form.add_child(_style_edit)

	_lyrics_edit = _styled_line_edit("可选：歌词或主题（留空则生成纯旋律）")
	_lyrics_edit.text = keep_lyrics
	form.add_child(_lyrics_edit)

	_melody_gen_btn = UIKit.button("生成", UIKit.COL_AI, 15)
	_melody_gen_btn.pressed.connect(_request_melody)
	form.add_child(_melody_gen_btn)
	vb.add_child(form)

	_melody_status = UIKit.label(_default_melody_status(), 12, UIKit.COL_MUTED)
	vb.add_child(_melody_status)

	# ── 导入本地 WAV 旋律（仅限 WAV：波形/自动对齐需要 PCM 数据）──
	var imp_row = HBoxContainer.new()
	imp_row.add_theme_constant_override("separation", 10)
	var imp_btn = UIKit.button("📂 导入 WAV 旋律", UIKit.COL_NEON, 13)
	imp_btn.pressed.connect(func(): _import_dialog.popup_centered_ratio(0.7))
	imp_row.add_child(imp_btn)
	imp_row.add_child(UIKit.label("仅支持 WAV（波形标记与自动对齐需要 PCM 数据）", 11, UIKit.COL_MUTED))
	vb.add_child(imp_row)

	# ── 播放器（仅当已有旋律时显示）──
	if _melody_path != "" and FileAccess.file_exists(_melody_path):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)

		_melody_play_btn = UIKit.button("▶ 播放旋律", UIKit.COL_NEON, 15)
		_melody_play_btn.pressed.connect(_toggle_melody_play)
		row.add_child(_melody_play_btn)

		_melody_progress = ProgressBar.new()
		_melody_progress.min_value = 0.0
		_melody_progress.max_value = 1.0
		_melody_progress.value = 0.0
		_melody_progress.show_percentage = false
		_melody_progress.custom_minimum_size = Vector2(160, 22)
		_melody_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_melody_progress)

		row.add_child(_volume_slider("旋律", 1.0, func(v): Audio.set_melody_volume(v)))
		row.add_child(_volume_slider("节奏", Audio.rhythm_volume, func(v): Audio.set_rhythm_volume(v)))

		var dl = UIKit.button("💾 下载", UIKit.COL_NEON, 15)
		dl.pressed.connect(func(): _melody_dialog.popup())
		row.add_child(dl)

		var del = UIKit.button("🗑", UIKit.COL_AI, 15)
		del.pressed.connect(_delete_melody)
		row.add_child(del)

		vb.add_child(row)

		# ── 波形音轨（点击标记强拍,第 1 个为对齐锚点;标 2 个可反推 BPM）──
		# ── 目标 + 步骤引导（旋律存在时始终显示，白话化）──
	vb.add_child(UIKit.label("目标：让垃圾鼓点和 AI 旋律踩在同一拍上", 12, UIKit.COL_TEXT))
	var steps = VBoxContainer.new()
	steps.add_theme_constant_override("separation", 2)
	_step_labels = []
	_step_labels.append(_make_step("① 生成或导入一段旋律"))
	_step_labels.append(_make_step("② 点「自动对齐」标出节拍点（或手动在波形上点）"))
	_step_labels.append(_make_step("③ 点「设为节奏 BPM」，鼓点即与旋律同速、并在第一节拍点进入"))
	for s in _step_labels:
		steps.add_child(s)
	vb.add_child(steps)
	_update_step_checklist()

	var wave_data = Audio.melody_waveform(_melody_path, 900)
	if wave_data.peaks.size() > 0:
		var hint = UIKit.label("在波形上点击标记强拍：第 1 个是对齐锚点（播放节奏时从这里进）；相邻两个强拍可反推 BPM", 11, UIKit.COL_MUTED)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(hint)

		var tool = HBoxContainer.new()
		tool.add_theme_constant_override("separation", 8)
		var zout = UIKit.button("− 缩小", UIKit.COL_MUTED, 13)
		zout.pressed.connect(func(): _set_wave_zoom(_melody_wave_zoom / 2.0))
		tool.add_child(zout)
		var zin = UIKit.button("＋ 放大", UIKit.COL_MUTED, 13)
		zin.pressed.connect(func(): _set_wave_zoom(_melody_wave_zoom * 2.0))
		tool.add_child(zin)
		var auto = UIKit.button("🎯 自动对齐", UIKit.COL_NEON, 13)
		auto.pressed.connect(func(): _auto_align_melody(true))
		tool.add_child(auto)
		var redet = UIKit.button("🔄 重新检测", UIKit.COL_MUTED, 13)
		redet.pressed.connect(func(): _auto_align_melody(true))
		tool.add_child(redet)
		var clr = UIKit.button("清除强拍", UIKit.COL_AI, 13)
		clr.pressed.connect(_clear_melody_marks)
		tool.add_child(clr)
		_melody_bpm_label = UIKit.label("", 13, UIKit.COL_NEON)
		_melody_bpm_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		tool.add_child(_melody_bpm_label)
		var setbpm = UIKit.button("设为节奏 BPM", UIKit.COL_NEON, 13)
		setbpm.pressed.connect(_set_rhythm_bpm_from_melody)
		tool.add_child(setbpm)
		vb.add_child(tool)

		var scroll = ScrollContainer.new()
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		scroll.custom_minimum_size = Vector2(0, 100)
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_melody_wave = MelodyWave.new()
		_melody_wave.setup(wave_data.peaks, wave_data.duration, _downbeat_marks, _melody_wave_zoom)
		_melody_wave.mark_added.connect(_on_melody_mark_added)
		scroll.add_child(_melody_wave)
		vb.add_child(scroll)
		_update_melody_bpm_label()
	else:
			vb.add_child(UIKit.label("（该旋律非 WAV，暂不支持波形标记；仍可播放/下载）", 11, UIKit.COL_MUTED))

func _volume_slider(name_text: String, initial: float, on_change: Callable) -> Control:
	var box = HBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var l = UIKit.label(name_text, 12, UIKit.COL_MUTED)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	var sl = HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.05
	sl.value = initial
	sl.custom_minimum_size = Vector2(90, 20)
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(v): on_change.call(v))
	box.add_child(sl)
	return box

func _default_melody_status() -> String:
	if not _melody_gen.is_configured():
		return "云端生成未配置；可导入本地音频，或使用上方的离线智能续写。"
	if _melody_path != "" and FileAccess.file_exists(_melody_path):
		if _melody_tags != "":
			return "已有旋律 · %s" % _melody_tags
		return "已有旋律"
	return "填写风格后点「生成」，生成后可在下方波形上点击标记强拍来对齐节奏"

func _set_melody_status(msg: String) -> void:
	if _melody_status != null and is_instance_valid(_melody_status):
		_melody_status.text = msg

# ── 强拍标记 / BPM 反推 ─────────────────────────────────────
func _set_wave_zoom(z: float) -> void:
	_melody_wave_zoom = clampf(z, 1.0, 16.0)
	if _melody_wave != null and is_instance_valid(_melody_wave):
		_melody_wave.set_zoom(_melody_wave_zoom)

func _on_melody_mark_added(t: float) -> void:
	_downbeat_marks.append(t)
	_downbeat_marks.sort()
	_melody_bpm_applied = false
	GameState.set_melody_marks(_current_pid, _downbeat_marks)
	if _melody_wave != null and is_instance_valid(_melody_wave):
		_melody_wave.set_marks(_downbeat_marks)
	_update_melody_bpm_label()
	_update_step_checklist()

func _clear_melody_marks() -> void:
	_downbeat_marks = []
	_melody_bpm_applied = false
	GameState.set_melody_marks(_current_pid, _downbeat_marks)
	if _melody_wave != null and is_instance_valid(_melody_wave):
		_melody_wave.set_marks(_downbeat_marks)
	_update_melody_bpm_label()
	_update_step_checklist()
	UIKit.toast(self, "已清除强拍标记", UIKit.COL_MUTED)

## 把 BPM（float）格式化成字符串：整数就显示整数，否则保留 1 位小数。
## 注意：Godot 的 % 运算符不支持 %g，故用此函数替代。
func _fmt_bpm(v: float) -> String:
	var r: float = round(v * 10.0) / 10.0
	if abs(r - round(r)) < 0.001:
		return str(int(r))
	return String.num(r, 1)

## 由相邻强拍间距反推旋律 BPM（相邻强拍视为 1 小节 = 1 个节奏循环 = 4 拍）。
func _melody_bpm() -> float:
	if _downbeat_marks.size() < 2:
		return 0.0
	var total = 0.0
	var cnt = 0
	for i in range(_downbeat_marks.size() - 1):
		var d = float(_downbeat_marks[i + 1]) - float(_downbeat_marks[i])
		if d > 0.05:
			total += d
			cnt += 1
	if cnt == 0:
		return 0.0
	return 240.0 / (total / cnt)

func _update_melody_bpm_label() -> void:
	if _melody_bpm_label == null or not is_instance_valid(_melody_bpm_label):
		return
	var b = _melody_bpm()
	_melody_bpm_label.text = ("检测到旋律约 " + _fmt_bpm(b) + " BPM") if b > 0.0 else "标 2 个强拍可反推 BPM"

func _set_rhythm_bpm_from_melody() -> void:
	var b = _melody_bpm()
	if b <= 0.0:
		UIKit.toast(self, "先点「自动对齐」或手动标 2 个节拍点以反推 BPM", UIKit.COL_MUTED)
		return
	_set_bpm(b)
	_melody_bpm_applied = true
	_update_step_checklist()
	UIKit.toast(self, "垃圾节奏已设为 " + _fmt_bpm(Audio.bpm) + " BPM", UIKit.COL_NEON)

## 一键自动检测并标出节拍点（覆盖当前标记，可微调）。show_toast=false 用于生成/打开时静默预填。
func _auto_align_melody(show_toast: bool = true) -> void:
	if _melody_path == "" or not FileAccess.file_exists(_melody_path):
		if show_toast:
			UIKit.toast(self, "请先生成或导入旋律", UIKit.COL_MUTED)
		return
	var res = Audio.detect_downbeats(_melody_path)
	if res.marks.size() == 0:
		if show_toast:
			UIKit.toast(self, "自动检测失败，可手动在波形上点节拍点", UIKit.COL_AI)
		return
	_downbeat_marks = res.marks
	_melody_bpm_applied = false
	GameState.set_melody_marks(_current_pid, _downbeat_marks)
	if _melody_wave != null and is_instance_valid(_melody_wave):
		_melody_wave.set_marks(_downbeat_marks)
	_update_melody_bpm_label()
	_update_step_checklist()
	if show_toast:
		UIKit.toast(self, "已自动标出 " + str(_downbeat_marks.size()) + " 个节拍点（BPM≈" + _fmt_bpm(res.bpm) + "），可手动微调或点「设为节奏 BPM」", UIKit.COL_NEON)

## 生成一条步骤说明标签（带「完成态」元数据）。
func _make_step(text: String) -> Label:
	var l = UIKit.label(text, 11, UIKit.COL_MUTED)
	l.set_meta("base", text)
	return l

## 根据当前状态刷新 3 步清单的勾选态。
func _update_step_checklist() -> void:
	if _step_labels == null or _step_labels.is_empty():
		return
	var has_melody = _melody_path != "" and FileAccess.file_exists(_melody_path)
	var has_marks = _downbeat_marks.size() >= 2
	_set_step(_step_labels[0], has_melody)
	_set_step(_step_labels[1], has_marks)
	_set_step(_step_labels[2], _melody_bpm_applied)

func _set_step(lbl: Label, done: bool) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	var base = lbl.get_meta("base", "")
	lbl.text = ("✓ " if done else "○ ") + base
	lbl.modulate = Color(1, 1, 1) if done else Color(0.72, 0.72, 0.72)

func _request_melody() -> void:
	if _mode != MODE_EDIT or _current_pid == "":
		return
	if _generating:
		UIKit.toast(self, "旋律生成中，请稍候…", UIKit.COL_AI)
		return
	var style = ""
	if _style_edit != null and is_instance_valid(_style_edit):
		style = _style_edit.text.strip_edges()
	if style == "":
		style = "instrumental, groovy, electronic"
	var lyrics = ""
	if _lyrics_edit != null and is_instance_valid(_lyrics_edit):
		lyrics = _lyrics_edit.text.strip_edges()
	if lyrics == "":
		lyrics = "[intro]\n(instrumental)\n[outro]\n"
	_melody_tags = style
	_generating = true
	_gen_elapsed = 0.0
	if _melody_gen_btn != null and is_instance_valid(_melody_gen_btn):
		_melody_gen_btn.disabled = true
	_set_melody_status("提交生成任务中…")
	var save_path = "user://projects/%s_melody.mp3" % _current_pid
	_melody_gen.generate(lyrics, _melody_tags, save_path)

func _on_melody_submitted(task_id: String) -> void:
	_set_melody_status("已提交（任务 %s）· 生成中，通常需 1~3 分钟…" % task_id.left(12))

func _on_melody_downloaded(path: String) -> void:
	_generating = false
	_melody_path = path
	GameState.set_melody(_current_pid, path, _melody_tags)
	_build_melody_block()
	_auto_align_melody(false)
	UIKit.toast(self, "旋律生成成功！已自动标出节拍点，点「设为节奏 BPM」即可对齐", UIKit.COL_NEON)

func _on_melody_error(msg: String) -> void:
	_generating = false
	if _melody_gen_btn != null and is_instance_valid(_melody_gen_btn):
		_melody_gen_btn.disabled = false
	_set_melody_status("生成失败：%s" % msg)
	UIKit.toast(self, "旋律生成失败：%s" % msg, UIKit.COL_AI)

func _on_melody_tick() -> void:
	if _generating:
		_gen_elapsed += _melody_tick.wait_time
		if int(_gen_elapsed) % 2 == 0:
			_set_melody_status("生成中…已等待 %ds（最长 5 分钟）" % int(_gen_elapsed))
	if _melody_progress != null and is_instance_valid(_melody_progress):
		var len_s = Audio.melody_length()
		if len_s > 0.0:
			_melody_progress.value = clampf(Audio.melody_position() / len_s, 0.0, 1.0)
		if _melody_play_btn != null and is_instance_valid(_melody_play_btn):
			_melody_play_btn.text = "■ 停止旋律" if Audio.is_melody_playing() else "▶ 播放旋律"
	# 波形播放头
	if _melody_wave != null and is_instance_valid(_melody_wave):
		_melody_wave.set_playhead(Audio.melody_position() if Audio.is_melody_playing() else -1.0)

func _toggle_melody_play() -> void:
	if Audio.is_melody_playing():
		Audio.stop_melody()
	else:
		if not Audio.play_melody(_melody_path):
			UIKit.toast(self, "旋律文件读取失败", UIKit.COL_AI)

func _delete_melody() -> void:
	Audio.stop_melody()
	GameState.remove_melody(_current_pid)   # 已连带清 melody_marks
	_melody_path = ""
	_melody_tags = ""
	_downbeat_marks = []
	_rhythm_sync_pending = false
	_melody_progress = null
	_melody_play_btn = null
	_melody_wave = null
	_melody_bpm_label = null
	_build_melody_block()
	UIKit.toast(self, "已删除旋律", UIKit.COL_AI)

func _on_melody_save_selected(path: String) -> void:
	if _melody_path == "" or not FileAccess.file_exists(_melody_path):
		UIKit.toast(self, "没有可导出的旋律", UIKit.COL_AI)
		return
	var src = FileAccess.open(_melody_path, FileAccess.READ)
	if src == null:
		UIKit.toast(self, "读取旋律失败", UIKit.COL_AI)
		return
	var bytes = src.get_buffer(src.get_length())
	src.close()
	var dst = FileAccess.open(path, FileAccess.WRITE)
	if dst == null:
		UIKit.toast(self, "导出失败，检查路径权限", UIKit.COL_AI)
		return
	dst.store_buffer(bytes)
	dst.close()
	UIKit.toast(self, "已导出 MP3：%s" % path, UIKit.COL_NEON)

## 导入本地 WAV 作为本项目旋律（仅限 WAV：波形/自动对齐需 PCM 数据）。
func _on_melody_import_selected(path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		UIKit.toast(self, "未选择有效文件", UIKit.COL_AI)
		return
	# 校验确为 WAV：前 4 字节 "RIFF" 且偏移 8 处为 "WAVE"
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		UIKit.toast(self, "文件读取失败", UIKit.COL_AI)
		return
	var head = f.get_buffer(12)
	f.close()
	var is_wav = head.size() >= 12 \
		and head.slice(0, 4).get_string_from_ascii() == "RIFF" \
		and head.slice(8, 12).get_string_from_ascii() == "WAVE"
	if not is_wav:
		UIKit.toast(self, "仅支持 WAV 格式（检测到非 WAV 文件）", UIKit.COL_AI)
		return
	Audio.stop_melody()
	_melody_path = path
	_melody_tags = "导入: " + path.get_file()
	GameState.set_melody(_current_pid, _melody_path, _melody_tags)
	_build_melody_block()
	_auto_align_melody(false)
	UIKit.toast(self, "已导入 WAV 旋律，已自动标出节拍点", UIKit.COL_NEON)

## Apply NoiseSuppressor to the recorded sequencer output.
## Uses the same streaming spectral denoiser as the mic recording pipeline.
func _denoise_recording(buf: PackedFloat32Array) -> PackedFloat32Array:
	if buf.size() == 0:
		return buf
	var suppressor := NOISE_SUPPRESSOR.new(float(Audio.MIX_RATE))
	suppressor.suppression_strength = 1.15
	suppressor.isolation_strength = 0.35
	suppressor.minimum_gain_db = -24.0
	var out := suppressor.process_mono(buf)
	var tail := suppressor.flush()
	if tail.size() > 0:
		var combined := PackedFloat32Array()
		combined.resize(out.size() + tail.size())
		for i in out.size():
			combined[i] = out[i]
		for i in tail.size():
			combined[out.size() + i] = tail[i]
		out = combined
	return out
