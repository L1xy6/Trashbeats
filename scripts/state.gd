extends Node
## GameState (autoload) — shared prototype state: instrument definitions,
## collection tracking, pattern persistence. All state survives app restart via
## ConfigFile at user://trashbeats_save.cfg.

signal collected_changed(id: String)

const SAVE_PATH = "user://trashbeats_save.cfg"
const ARR_SAVE_PATH = "user://arrangements.cfg"   # 多项目编曲存档（独立文件）

const INSTRUMENTS = [
	{
		"id": "can", "mat": "ALUMINUM", "name": "铝制易拉罐 · 808", "short": "易拉罐",
		"color": Color("b8ff8a"),   # light green
		"fact": "铝罐是回收率最高的包装之一，再生铝比电解铝节能约 95%。",
	},
	{
		"id": "bottle", "mat": "PLASTIC", "name": "塑料瓶 · 电子木鱼", "short": "塑料瓶",
		"color": Color("7dff6a"),   # neon green (main theme)
		"fact": "一个 PET 塑料瓶自然降解需要约 450 年。",
	},
	{
		"id": "glass", "mat": "GLASS", "name": "玻璃瓶 · 清铃", "short": "玻璃瓶",
		"color": Color("5cdb4a"),   # medium green
		"fact": "玻璃可以 100% 无限循环再生，且不损失纯度。",
	},
	{
		"id": "box", "mat": "PAPER", "name": "纸箱 · 镲片", "short": "纸箱",
		"color": Color("3da828"),   # deep green
		"fact": "回收 1 吨废纸，约等于少砍 17 棵大树。",
	},
]

# Dynamically discovered instruments (not in the preset list)
var discovered = []
signal discovered_changed()

# User-recorded custom sounds (from the "自定义上传" column on the 寻宝 screen)
var custom_sounds = []
signal custom_sounds_changed()

# Favorites: which instruments are shown in the library (toggled via the star icon)
var favorites = {}
signal favorite_changed(id: String)

var collected = {}

# Arrangement projects (阶段 1 起：多项目编曲的数据模型，UI 在阶段 2 接入)
# 每个项目: {id, name, tracks:[乐器id...], patterns:{乐器id:[16步 或 null]}, bpm}
var projects = []

func _ready() -> void:
	for inst in INSTRUMENTS:
		collected[inst.id] = false
	_load_discovered()
	_load_custom()
	_load_state()
	_load_favorites()
	_ensure_default_favorites()
	_load_projects()
	_migrate_old_pattern()   # 旧 4 轨存档 → 第 1 个项目

## Add a dynamically discovered instrument from photo analysis
func add_discovered(mat_name: String, color: Color, fact: String) -> Dictionary:
	var entry = {
		"id": "disc_%d" % (discovered.size() + 1),
		"mat": mat_name,
		"name": "%s · 自定义" % mat_name,
		"short": mat_name,
		"color": color,
		"fact": fact,
	}
	discovered.append(entry)
	collected[entry.id] = false
	_save_discovered()
	discovered_changed.emit()
	return entry

## Add a user-recorded custom sound (from the 寻宝 "自定义上传" column).
## p_wav is a user:// path to a saved .wav; p_image is an optional local image path.
## p_id is an optional explicit id (used so the wav filename stays unique after deletions).
func add_custom_sound(p_name: String, p_image: String, p_wav: String, p_color: Color, p_id := "") -> Dictionary:
	var id = p_id if p_id != "" else "user_%d" % (custom_sounds.size() + 1)
	var entry = {
		"id": id, "mat": "CUSTOM", "name": p_name, "short": p_name,
		"color": p_color, "fact": "你亲手录制的垃圾声音。", "custom": true,
		"image": p_image, "wav": p_wav,
	}
	custom_sounds.append(entry)
	collected[entry.id] = true
	favorites[entry.id] = true
	_save_custom()
	_save_favorites()
	custom_sounds_changed.emit()
	return entry

## Next unique custom-sound id (avoids wav filename collisions after deletions).
func next_custom_id() -> String:
	var maxn = 0
	for c in custom_sounds:
		var m = String(c.id).trim_prefix("user_")
		if m.is_valid_int():
			maxn = maxi(maxn, m.to_int())
	return "user_%d" % (maxn + 1)

## Remove a user-recorded custom sound: drop it from state, delete its .wav file,
## and clear collected/favorites entries. Emits the relevant signals so the
## collect screen and library both refresh.
func remove_custom_sound(id: String) -> void:
	var idx = -1
	for i in custom_sounds.size():
		if custom_sounds[i].id == id:
			idx = i
			break
	if idx < 0:
		return
	var entry = custom_sounds[idx]
	var wav_path: String = entry.get("wav", "")
	if wav_path != "" and FileAccess.file_exists(wav_path):
		DirAccess.remove_absolute(wav_path)
	custom_sounds.remove_at(idx)
	collected.erase(id)
	favorites.erase(id)
	_save_custom()
	_save_favorites()
	_save_state()
	custom_sounds_changed.emit()
	favorite_changed.emit(id)

## Track index of the i-th custom sound within all_instruments().
func custom_track(i: int) -> int:
	return INSTRUMENTS.size() + discovered.size() + i

func all_instruments() -> Array:
	return INSTRUMENTS + discovered + custom_sounds

func instrument(track: int) -> Dictionary:
	var all = all_instruments()
	if track < all.size():
		return all[track]
	return INSTRUMENTS[0]  # fallback

## Look up an instrument dictionary (name/color/...) by its id string.
## Used by the sequencer editor, which renders rows by project instrument ids.
func get_instrument(id: String) -> Dictionary:
	for inst in all_instruments():
		if inst.id == id:
			return inst
	return {}

# ── Favorites (library membership) ───────────────────────────────────

func is_favorite(id: String) -> bool:
	return favorites.get(id, false)

func toggle_favorite(id: String) -> void:
	favorites[id] = not favorites.get(id, false)
	_save_favorites()
	favorite_changed.emit(id)

## Instruments currently shown in the library (the favorited ones).
func favorite_instruments() -> Array:
	var out := []
	for inst in all_instruments():
		if favorites.get(inst.id, false):
			out.append(inst)
	return out

## Global track index of an instrument within all_instruments() (for Audio.trigger).
func global_track_of(id: String) -> int:
	var all = all_instruments()
	for i in all.size():
		if all[i].id == id:
			return i
	return -1

func _save_discovered() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		pass  # will create new
	if cfg.has_section("discovered"):
		cfg.erase_section("discovered")
	for i in discovered.size():
		var d = discovered[i]
		cfg.set_value("discovered", "mat_%d" % i, d.mat)
		cfg.set_value("discovered", "color_%d" % i, d.color.to_html())
		cfg.set_value("discovered", "fact_%d" % i, d.fact)
		cfg.set_value("discovered", "id_%d" % i, d.id)
	cfg.save(SAVE_PATH)

func _load_discovered() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var i = 0
	while cfg.has_section_key("discovered", "mat_%d" % i):
		var entry = {
			"id": cfg.get_value("discovered", "id_%d" % i, "disc_%d" % (i + 1)),
			"mat": cfg.get_value("discovered", "mat_%d" % i, "UNKNOWN"),
			"name": "%s · 自定义" % cfg.get_value("discovered", "mat_%d" % i, "UNKNOWN"),
			"short": cfg.get_value("discovered", "mat_%d" % i, "UNKNOWN"),
			"color": Color(cfg.get_value("discovered", "color_%d" % i, "#7dff6a")),
			"fact": cfg.get_value("discovered", "fact_%d" % i, ""),
		}
		discovered.append(entry)
		collected[entry.id] = false
		i += 1

func _save_custom() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		pass
	if cfg.has_section("custom_sounds"):
		cfg.erase_section("custom_sounds")
	for i in custom_sounds.size():
		var c = custom_sounds[i]
		cfg.set_value("custom_sounds", "name_%d" % i, c.name)
		cfg.set_value("custom_sounds", "id_%d" % i, c.id)
		cfg.set_value("custom_sounds", "color_%d" % i, c.color.to_html())
		cfg.set_value("custom_sounds", "wav_%d" % i, c.wav)
		cfg.set_value("custom_sounds", "image_%d" % i, c.image)
	cfg.save(SAVE_PATH)

func _load_custom() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var i = 0
	while cfg.has_section_key("custom_sounds", "id_%d" % i):
		var entry = {
			"id": cfg.get_value("custom_sounds", "id_%d" % i, "user_%d" % (i + 1)),
			"mat": "CUSTOM",
			"name": cfg.get_value("custom_sounds", "name_%d" % i, "我的声音"),
			"short": cfg.get_value("custom_sounds", "name_%d" % i, "我的声音"),
			"color": Color(cfg.get_value("custom_sounds", "color_%d" % i, "#ffcf5c")),
			"fact": "你亲手录制的垃圾声音。",
			"custom": true,
			"image": cfg.get_value("custom_sounds", "image_%d" % i, ""),
			"wav": cfg.get_value("custom_sounds", "wav_%d" % i, ""),
		}
		custom_sounds.append(entry)
		collected[entry.id] = true
		i += 1

func _save_favorites() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		pass
	if cfg.has_section("favorites"):
		cfg.erase_section("favorites")
	var i = 0
	for id in favorites.keys():
		cfg.set_value("favorites", "id_%d" % i, id)
		cfg.set_value("favorites", "on_%d" % i, favorites[id])
		i += 1
	cfg.save(SAVE_PATH)

func _load_favorites() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	var i = 0
	while cfg.has_section_key("favorites", "id_%d" % i):
		var id = cfg.get_value("favorites", "id_%d" % i, "")
		var on = cfg.get_value("favorites", "on_%d" % i, true)
		if id != "":
			favorites[id] = on
		i += 1

## Make sure all known instruments are favorited by default (presets + any
## previously-recorded custom sounds from an older save that predates favorites).
func _ensure_default_favorites() -> void:
	for inst in INSTRUMENTS:
		if not favorites.has(inst.id):
			favorites[inst.id] = true
	for c in custom_sounds:
		if not favorites.has(c.id):
			favorites[c.id] = true
	_save_favorites()

# ── Session persistence ──────────────────────────────────────────────

func _save_state() -> void:
	var cfg = ConfigFile.new()
	# This file also owns custom sounds, discoveries, favorites and old patterns.
	# Updating collection flags must preserve those independent sections.
	if cfg.load(SAVE_PATH) != OK:
		pass
	if cfg.has_section("collected"):
		cfg.erase_section("collected")
	for id in collected:
		cfg.set_value("collected", id, collected[id])
	cfg.set_value("meta", "version", 1)
	cfg.save(SAVE_PATH)

func _load_state() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for id in collected:
		collected[id] = cfg.get_value("collected", id, false)
	# emit signals so UI refreshes
	for inst in INSTRUMENTS:
		if collected.get(inst.id, false):
			collected_changed.emit(inst.id)

func reset_progress() -> void:
	for inst in INSTRUMENTS:
		collected[inst.id] = false
	custom_sounds.clear()
	favorites = {}
	DirAccess.remove_absolute(SAVE_PATH)
	for inst in INSTRUMENTS:
		collected_changed.emit(inst.id)
	custom_sounds_changed.emit()
	_ensure_default_favorites()   # repopulate preset favorites + save
	favorite_changed.emit("")

# ── Sequencer pattern persistence ────────────────────────────────────

func save_patterns(cells: Array, bpm: float) -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		# no existing save — build from current collected state
		for id in collected:
			cfg.set_value("collected", id, collected[id])
	for t in cells.size():
		for s in cells[t].size():
			var on: bool = cells[t][s].on
			cfg.set_value("pat_t%d" % t, "s%d_on" % s, on)
			if on:
				cfg.set_value("pat_t%d" % t, "s%d_pitch" % s, cells[t][s].pitch)
				cfg.set_value("pat_t%d" % t, "s%d_ai" % s, cells[t][s].ai)
	cfg.set_value("meta", "bpm", bpm)
	cfg.save(SAVE_PATH)

func load_patterns() -> Dictionary:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}
	var has_patterns := false
	for t in 4:
		has_patterns = has_patterns or cfg.has_section("pat_t%d" % t)
	if not has_patterns:
		return {}  # A fresh favorites/collection save is not a legacy arrangement.
	var pats = []
	for t in 4:
		var row = []
		for s in 16:
			row.append({
				"on": cfg.get_value("pat_t%d" % t, "s%d_on" % s, false),
				"pitch": cfg.get_value("pat_t%d" % t, "s%d_pitch" % s, 0),
				"ai": cfg.get_value("pat_t%d" % t, "s%d_ai" % s, false),
			})
		pats.append(row)
	return {"patterns": pats, "bpm": cfg.get_value("meta", "bpm", 120.0)}

# ── Arrangement projects (多项目编曲) ─────────────────────────────────
# 阶段 1：纯数据层，先建好并存读；阶段 2 才把编曲页接到这套模型。
# patterns 按乐器 id 存 16 步（而非固定 4 轨），这样加/删轨道不会破坏数据。

## p_steps：每循环步数。16 = 4/4 拍（4 组 × 4 格），12 = 3/4 拍（3 组 × 4 格）。
func new_project(name: String, p_steps: int = 16) -> String:
	var id = _next_project_id()
	var default_tracks = []
	for inst in INSTRUMENTS:
		default_tracks.append(inst.id)
	var proj = {
		"id": id,
		"name": name if name != "" else "未命名编曲",
		"tracks": default_tracks,
		"patterns": {},
		"bpm": 120.0,
		"steps": clampi(p_steps, 4, 16),
	}
	projects.append(proj)
	_save_projects()
	return id

func _next_project_id() -> String:
	var maxn = 0
	for p in projects:
		var m = String(p.id).trim_prefix("proj_")
		if m.is_valid_int():
			maxn = maxi(maxn, m.to_int())
	return "proj_%d" % (maxn + 1)

func save_project(id: String, tracks: Array, patterns: Dictionary, bpm: float, rec_samples = null) -> void:
	for p in projects:
		if p.id == id:
			p.tracks = tracks
			p.patterns = patterns
			p.bpm = bpm
			# rec_samples 非空才更新录音；为 null 时保留原先的 recording_path（不误删）
			if rec_samples != null:
				var rp = "user://projects/%s_rec.wav" % id
				if Audio.write_wav(rp, rec_samples):
					p.recording_path = rp
			break
	_save_projects()

## 记录本项目的 AI 生成旋律：mp3 路径 + 生成时用的风格描述（供 UI 显示）。
func set_melody(id: String, path: String, tags: String) -> void:
	for p in projects:
		if p.id == id:
			p.melody_path = path
			p.melody_tags = tags
			break
	_save_projects()

## 保存本项目旋律的强拍标记（秒，升序；第 1 个为对齐锚点）。
func set_melody_marks(id: String, marks: Array) -> void:
	for p in projects:
		if p.id == id:
			p.melody_marks = marks
			break
	_save_projects()

## 删除本项目的 AI 旋律（删文件 + 清字段）。
func remove_melody(id: String) -> void:
	for p in projects:
		if p.id == id:
			var mp = p.get("melody_path", "")
			if mp != "" and FileAccess.file_exists(mp):
				DirAccess.remove_absolute(mp)
			p.erase("melody_path")
			p.erase("melody_tags")
			p.erase("melody_marks")
			break
	_save_projects()

## 删除项目的"已录制"音频（仅丢弃，不进乐器库）。保留 patterns/tracks。
func remove_recording(id: String) -> void:
	for p in projects:
		if p.id == id:
			var rp = p.get("recording_path", "")
			if rp != "" and FileAccess.file_exists(rp):
				DirAccess.remove_absolute(rp)
			p.erase("recording_path")
			break
	_save_projects()

## 保存本项目的麦克风录制路径（wav 已由调用方写入 user://）。
func save_mic(id: String, path: String) -> void:
	for p in projects:
		if p.id == id:
			p.mic_path = path
			break
	_save_projects()

## 删除本项目的麦克风录制（删文件 + 清字段）。
func remove_mic(id: String) -> void:
	for p in projects:
		if p.id == id:
			var mp = p.get("mic_path", "")
			if mp != "" and FileAccess.file_exists(mp):
				DirAccess.remove_absolute(mp)
			p.erase("mic_path")
			break
	_save_projects()

func load_project(id: String) -> Dictionary:
	for p in projects:
		if p.id == id:
			return p
	return {}

func list_projects() -> Array:
	var out = []
	for p in projects:
		out.append({"id": p.id, "name": p.name, "bpm": p.bpm, "tracks": p.tracks, "steps": p.get("steps", 16)})
	return out

func delete_project(id: String) -> void:
	var rp = ""
	var mp = ""
	for i in projects.size():
		if projects[i].id == id:
			rp = projects[i].get("recording_path", "")
			mp = projects[i].get("melody_path", "")
			projects.remove_at(i)
			break
	if rp != "" and FileAccess.file_exists(rp):
		DirAccess.remove_absolute(rp)
	if mp != "" and FileAccess.file_exists(mp):
		DirAccess.remove_absolute(mp)
	_save_projects()

func rename_project(id: String, name: String) -> void:
	for p in projects:
		if p.id == id:
			p.name = name
			break
	_save_projects()

func _save_projects() -> void:
	var cfg = ConfigFile.new()
	for p in projects:
		var sec = "proj_%s" % p.id
		cfg.set_value(sec, "name", p.name)
		cfg.set_value(sec, "bpm", p.bpm)
		cfg.set_value(sec, "tracks", p.tracks)
		cfg.set_value(sec, "recording_path", p.get("recording_path", ""))
		cfg.set_value(sec, "mic_path", p.get("mic_path", ""))
		cfg.set_value(sec, "steps", p.get("steps", 16))
		cfg.set_value(sec, "melody_path", p.get("melody_path", ""))
		cfg.set_value(sec, "melody_tags", p.get("melody_tags", ""))
		cfg.set_value(sec, "melody_marks", p.get("melody_marks", []))
		var pats: Dictionary = p.patterns
		for tid in p.tracks:
			var cells = pats.get(tid, [])
			var arr = []
			for s in 16:
				var e = cells[s] if s < cells.size() else null
				if e == null:
					e = {"on": false, "pitch": 0, "ai": false}
				arr.append(e)
			cfg.set_value(sec, "pat_%s" % tid, arr)
	cfg.save(ARR_SAVE_PATH)

func _load_projects() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(ARR_SAVE_PATH) != OK:
		projects = []
		return
	projects = []
	for sec in cfg.get_sections():
		if not sec.begins_with("proj_"):
			continue
		var id = sec.trim_prefix("proj_")
		var tracks = cfg.get_value(sec, "tracks", [])
		var bpm = cfg.get_value(sec, "bpm", 120.0)
		var name = cfg.get_value(sec, "name", "未命名编曲")
		var patterns = {}
		for tid in tracks:
			var raw_arr = cfg.get_value(sec, "pat_%s" % tid, [])
			var norm = []
			for s in 16:
				var e = raw_arr[s] if s < raw_arr.size() else null
				if e is Dictionary and e.get("on", false):
					norm.append(e)
				else:
					norm.append(null)
			patterns[tid] = norm
		projects.append({
			"id": id, "name": name, "tracks": tracks, "patterns": patterns, "bpm": bpm,
			"recording_path": cfg.get_value(sec, "recording_path", ""),
		"mic_path": cfg.get_value(sec, "mic_path", ""),
			"steps": cfg.get_value(sec, "steps", 16),
			"melody_path": cfg.get_value(sec, "melody_path", ""),
			"melody_tags": cfg.get_value(sec, "melody_tags", ""),
			"melody_marks": cfg.get_value(sec, "melody_marks", []),
		})

## 把旧的 4 轨 pattern（SAVE_PATH 里的 pat_t*）迁移成第 1 个项目。
## 只在确实没有项目时执行一次，迁移后清除旧键，避免重复迁移。
func _migrate_old_pattern() -> void:
	if projects.size() > 0:
		return
	var old = load_patterns()
	if not old.has("patterns"):
		return
	var pats = old.patterns
	var id = "proj_1"
	var tracks = []
	for inst in INSTRUMENTS:
		tracks.append(inst.id)
	var patterns = {}
	for t in 4:
		var tid = INSTRUMENTS[t].id
		var arr = []
		for s in 16:
			var e = pats[t][s]
			if e.on:
				arr.append({"on": true, "pitch": e.pitch, "ai": e.ai})
			else:
				arr.append(null)
		patterns[tid] = arr
	projects.append({"id": id, "name": "我的第一段编曲", "tracks": tracks, "patterns": patterns, "bpm": old.bpm})
	_save_projects()
	_clear_old_patterns()

func _clear_old_patterns() -> void:
	var cfg = ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for t in 4:
		if cfg.has_section("pat_t%d" % t):
			cfg.erase_section("pat_t%d" % t)
	cfg.save(SAVE_PATH)

# ── Collection tracking ──────────────────────────────────────────────

func mark_collected(id: String) -> void:
	if collected.get(id, false):
		return
	collected[id] = true
	_save_state()
	collected_changed.emit(id)

func collected_count() -> int:
	var n = 0
	for v in collected.values():
		if v:
			n += 1
	return n

# instrument() is defined above with dynamic instrument support
