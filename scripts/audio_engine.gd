extends Node
## Audio (autoload) — sample-accurate 16-step sequencer clock and procedural
## mixer built on AudioStreamGenerator. Replaces the web prototype's Web Audio
## buffer loop (index.html #seq): notes are mixed at exact sample offsets so
## the playhead never drifts.

signal step_changed(step: int)
signal transport_changed(playing: bool)

const MIX_RATE = 44100
const STEPS = 16    # 步数上限（数组按此分配）
const TRACKS = 12   # 4 presets + up to 8 custom (recorded) tracks

var steps = 16      # 当前循环步数：16 = 4/4 拍，12 = 3/4 拍（按项目切换）
var bpm = 120.0
var playing = false
var current_step = 0

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _sample_counter = 0
var _next_step_pos = 0
var _voices: Array = []        # [{"samples": PackedFloat32Array, "pos": int}]
var _patterns: Array = []      # [track][step] -> null or {"pitch": int, "vel": float}
var _recorded_samples = {}    # track_id → PackedFloat32Array (real microphone recordings)
var recording = false         # 是否正在抓取播放输出录制
var _rec_buffer = PackedFloat32Array()   # 录制缓冲（单声道 float32）
var _oneshot_player: AudioStreamPlayer = null   # 播放"已录制"整段音频
var _melody_player: AudioStreamPlayer = null    # 播放 AI 生成旋律（MP3，独立于混音管线）
var _mic_player: AudioStreamPlayer = null        # 播放麦克风录制片段（随歌曲回放，独立播放器避免与 one-shot 冲突）
var rhythm_volume = 1.0       # 节奏网格音量乘数 0~1（旋律与节奏做平衡用）

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	var gen = AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_player.stream = gen
	add_child(_player)
	_player.play()
	_playback = _player.get_stream_playback()
	_patterns.resize(TRACKS)
	for t in TRACKS:
		var row = []
		row.resize(STEPS)
		row.fill(null)
		_patterns[t] = row
	_load_recorded_samples()

func samples_per_step() -> int:
	# 每循环固定 4 拍：每拍格数 = steps / 4（16 格→每格 1/4 拍，12 格→每格 1/3 拍）
	return max(1, int(MIX_RATE * 60.0 / bpm / (steps / 4.0)))

func set_cell(track: int, step: int, data) -> void:
	_patterns[track][step] = data

func clear_pattern() -> void:
	for t in TRACKS:
		_patterns[t].fill(null)

func start() -> void:
	current_step = 0
	_next_step_pos = _sample_counter + int(0.08 * MIX_RATE)
	if not playing:
		playing = true
		transport_changed.emit(true)

func stop() -> void:
	if playing:
		playing = false
		transport_changed.emit(false)

## Immediate one-shot (library preview, collect-screen hits, cell audition).
func trigger(track: int, pitch: int = 0, vel: float = 1.0) -> void:
	_queue_voice(track, pitch, vel, 0)

## Load a real microphone recording from disk and map it to a track.
func load_sample(track: int, path: String) -> void:
	var s = _read_wav_samples(path)
	if s.size() > 0:
		_recorded_samples[track] = _trim_hit(s)

## Immediately play an arbitrary recorded sample (one-shot preview).
func play_sample(samples: PackedFloat32Array) -> void:
	if samples.size() == 0:
		return
	_voices.append({"samples": samples, "pos": 0})

## Store a recorded sample directly from in-memory floats (no file roundtrip).
## Used right after recording so the library preview works this session without
## depending on reading the saved .wav back from disk.
func load_sample_from_array(track: int, samples: PackedFloat32Array) -> void:
	if samples.size() == 0:
		return
	_recorded_samples[track] = samples

## ── 录制播放输出（Phase 4）────────────────────────────
## 开始抓取播放混音。录到的 = 扬声器实际播出（含录制途中手动改的格子）。
func start_recording() -> void:
	_rec_buffer = PackedFloat32Array()
	recording = true

func stop_recording() -> PackedFloat32Array:
	recording = false
	return _rec_buffer

func is_recording() -> bool:
	return recording

## 连续播放一段已录制的音频（不走 16 格网格）。
func play_one_shot(samples: PackedFloat32Array) -> void:
	if samples.size() == 0:
		return
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = _float32_to_pcm16(samples)
	if _oneshot_player == null:
		_oneshot_player = AudioStreamPlayer.new()
		add_child(_oneshot_player)
	_oneshot_player.stream = wav
	_oneshot_player.play()

## 连续播放麦克风录制片段（随歌曲回放，独立于"已录制"的 one-shot 播放器）。
func play_mic(samples: PackedFloat32Array) -> void:
	if samples.size() == 0:
		return
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = _float32_to_pcm16(samples)
	if _mic_player == null:
		mic_player_create()
	_mic_player.stream = wav
	_mic_player.play()

func mic_player_create() -> void:
	_mic_player = AudioStreamPlayer.new()
	add_child(_mic_player)

func stop_mic() -> void:
	if _mic_player != null:
		_mic_player.stop()

func is_mic_playing() -> bool:
	return _mic_player != null and _mic_player.playing

## ── AI 旋律播放（阶段 5）──────────────────────────────
## 旋律走独立 AudioStreamPlayer，不经过 _process() 混音管线，
## 因此**不会**被 _rec_buffer 录进去（这是与用户确认过的设计）。
func _ensure_melody_player() -> AudioStreamPlayer:
	if _melody_player == null:
		_melody_player = AudioStreamPlayer.new()
		add_child(_melody_player)
	return _melody_player

## 载入并播放旋律文件（user:// 或绝对路径皆可）。
## 注意：天琴 API 字段/文件名都叫 mp3，但实测返回的是 **WAV**（48k/16bit/stereo + AIGC 元数据块）。
## 这里按字节真实格式嗅探后选对应 Godot 4.4+ *_from_buffer 解码器，避免再踩 .new()+.data 的坑。
func play_melody(audio_path: String) -> bool:
	var bytes = _read_bytes(audio_path)
	if bytes.size() == 0:
		return false
	var stream = _stream_from_bytes(bytes)
	if stream == null:
		push_warning("play_melody: 不支持的音频格式（%d 字节，头=%s）" % [bytes.size(), bytes.slice(0, 8).hex_encode()])
		return false
	var pl = _ensure_melody_player()
	pl.stream = stream
	pl.play()
	return true

## 按文件头嗅探格式并构造对应 AudioStream（Godot 4.4+ 各 *_from_buffer 静态构造）。
## 天琴实测返 WAV；保留 MP3/OGG 分支以兼容 API 可能的其它输出。
static func _stream_from_bytes(bytes: PackedByteArray) -> AudioStream:
	if bytes.size() < 12:
		return null
	# RIFF....WAVE → WAV（立体声/48k/16bit 及未知块（如 AIGC）Godot 内置 WAV 加载器自动跳过）
	if bytes.slice(0, 4) == PackedByteArray([0x52, 0x49, 0x46, 0x46]) \
			and bytes.slice(8, 12) == PackedByteArray([0x57, 0x41, 0x56, 0x45]):
		return AudioStreamWAV.load_from_buffer(bytes)
	# ID3v2 头 或 MP3 帧同步字 0xFF Ex → MP3
	if bytes.slice(0, 3) == PackedByteArray([0x49, 0x44, 0x33]) \
			or (bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0):
		return AudioStreamMP3.load_from_buffer(bytes)
	# OggS → OGG Vorbis
	if bytes.slice(0, 4) == PackedByteArray([0x4F, 0x67, 0x67, 0x53]):
		return AudioStreamOggVorbis.load_from_buffer(bytes)
	return null

func stop_melody() -> void:
	if _melody_player != null:
		_melody_player.stop()

func is_melody_playing() -> bool:
	return _melody_player != null and _melody_player.playing

func melody_position() -> float:
	if _melody_player == null:
		return 0.0
	return _melody_player.get_playback_position()

func melody_length() -> float:
	if _melody_player == null or _melody_player.stream == null:
		return 0.0
	return _melody_player.stream.get_length()

func set_melody_volume(v: float) -> void:
	var pl = _ensure_melody_player()
	if v <= 0.001:
		pl.volume_db = -80.0
	else:
		pl.volume_db = linear_to_db(clampf(v, 0.0, 1.0))

func set_rhythm_volume(v: float) -> void:
	rhythm_volume = clampf(v, 0.0, 1.0)

## Re-map all recorded samples from the current instrument list. Call after a
## custom sound is deleted, since remaining custom tracks shift their index.
func reload_recorded_samples() -> void:
	_recorded_samples = {}
	_load_recorded_samples()

func _load_recorded_samples() -> void:
	var sample_dir = "user://samples"
	if not DirAccess.dir_exists_absolute(sample_dir):
		return
	for t in GameState.INSTRUMENTS.size():
		var inst_id: String = GameState.INSTRUMENTS[t].id
		var path: String = "%s/%s.wav" % [sample_dir, inst_id]
		var s = _read_wav_samples(path)
		if s.size() > 0:
			_recorded_samples[t] = _trim_hit(s)
	# user-recorded custom sounds → mapped onto their all_instruments() track index
	var all = GameState.all_instruments()
	for i in all.size():
		if all[i].get("custom", false):
			var s = _read_wav_samples(all[i].get("wav", ""))
			if s.size() > 0:
				_recorded_samples[i] = _trim_hit(s)

## Convert 16-bit PCM PackedByteArray → PackedFloat32Array [-1, 1]
static func _pcm16_to_float32(bytes: PackedByteArray) -> PackedFloat32Array:
	var out = PackedFloat32Array()
	out.resize(bytes.size() / 2)
	for i in out.size():
		var lo = bytes[i * 2]
		var hi = bytes[i * 2 + 1]
		var v = float((hi << 8) | lo)
		if v >= 32768.0: v -= 65536.0
		out[i] = v / 32768.0
	return out

## 从 user:// wav 文件读取 16-bit PCM 样本。不依赖 ResourceLoader（user:// 不在
## 资源导入库，ResourceLoader.exists/load 对其不可靠，是重启后变默认鼓的根因）。
func _read_wav_samples(path: String) -> PackedFloat32Array:
	if not FileAccess.file_exists(path):
		return PackedFloat32Array()
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedFloat32Array()
	var bytes = f.get_buffer(f.get_length())
	f.close()
	return _decode_wav_pcm16(bytes)

## 解析标准 16-bit PCM WAV 的 "data" 块 → float32（Recorder 固定写 16-bit 单声道）。
static func _decode_wav_pcm16(bytes: PackedByteArray) -> PackedFloat32Array:
	var i = 12  # 跳过 RIFF(4)+size(4)+WAVE(4)
	while i + 8 <= bytes.size():
		var cid = bytes.slice(i, i + 4).get_string_from_ascii()
		var size = bytes[i + 4] | (bytes[i + 5] << 8) | (bytes[i + 6] << 16) | (bytes[i + 7] << 24)
		if cid == "data":
			return _pcm16_to_float32(bytes.slice(i + 8, i + 8 + size))
		i += 8 + size
		if (size & 1) != 0:
			i += 1  # chunk 对齐到偶数字节
	return PackedFloat32Array()

## 读取整个文件为字节（不依赖 ResourceLoader）。
static func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b = f.get_buffer(f.get_length())
	f.close()
	return b

## 从 .wav 文件读取样本为 float32（供"已录制"轨道回放）。
static func read_wav(path: String) -> PackedFloat32Array:
	return _decode_wav_pcm16(_read_bytes(path))

## 提取旋律波形（供编曲页波形音轨显示）。返回 {"peaks": PackedFloat32Array(0..1), "duration": 秒}。
## 仅 WAV 支持（AudioStreamWAV.data 暴露 PCM16）；MP3/OGG 无 PCM 则返回空，调用方做占位。
## 立体声只读左声道即可（显示用途），桶内做步进抽样近似峰值以提速（114s 也瞬时完成）。
static func melody_waveform(path: String, points: int = 900) -> Dictionary:
	var out = {"peaks": PackedFloat32Array(), "duration": 0.0}
	var bytes = _read_bytes(path)
	if bytes.size() == 0:
		return out
	var stream = _stream_from_bytes(bytes)
	if not (stream is AudioStreamWAV):
		return out
	var wav: AudioStreamWAV = stream
	var data: PackedByteArray = wav.data
	out.duration = stream.get_length()
	var bpf = 4 if wav.stereo else 2  # 每帧字节数（16-bit × 声道数）
	var frames = data.size() / bpf
	if frames <= 0 or out.duration <= 0.0:
		return out
	var peaks = PackedFloat32Array()
	peaks.resize(points)
	var per = float(frames) / float(points)
	var stride = maxi(1, int(per / 48.0))  # 每桶约抽样 48 次
	for p in points:
		var start = int(p * per)
		var end = mini(frames, int((p + 1) * per))
		var mx = 0.0
		var f = start
		while f < end:
			var idx = f * bpf
			var s = (data[idx + 1] << 8) | data[idx]  # little-endian 16-bit
			if s >= 32768:
				s -= 65536
			var a = abs(s) / 32768.0
			if a > mx:
				mx = a
			f += stride
		peaks[p] = mx
	out.peaks = peaks
	return out

## 自动检测旋律的强拍（小节起点）：返回 {anchor, marks:Array, bpm}。
## 思路：① 由振幅包络求 onset flux；② 自相关找单拍周期（60~180 BPM）；
## ③ 在 1 小节(4 拍)内扫描相位，取「每小节起点能量和」最大的偏移作为第一强拍(锚点)。
## 仅支持 WAV（非 WAV 返回空 marks）。mark 间距 = 1 小节 = 4 拍，与 _melody_bpm 反推一致。
static func detect_downbeats(path: String, points: int = 1800) -> Dictionary:
	var res := {"anchor": 0.0, "marks": [], "bpm": 0.0}
	var w = melody_waveform(path, points)
	var peaks = w.peaks
	var n: int = peaks.size()
	if n < 16:
		return res
	var dur: float = w.duration
	if dur <= 0.0:
		return res
	var dt: float = dur / float(n)
	# ① onset flux（正差分），并归一化
	var flux = PackedFloat32Array()
	flux.resize(n)
	var fmax := 0.0
	for i in n:
		var d = peaks[i] - (peaks[i - 1] if i > 0 else peaks[0])
		flux[i] = max(0.0, d)
		if flux[i] > fmax:
			fmax = flux[i]
	if fmax > 0.0:
		for i in n:
			flux[i] /= fmax
	# ② 自相关求单拍周期
	var fmin = 60.0 / 180.0
	var fmax_bpm = 60.0 / 60.0
	var lag_min: int = maxi(2, int(round(fmin / dt)))
	var lag_max: int = mini(n - 1, int(round(fmax_bpm / dt)))
	if lag_max <= lag_min:
		return res
	var best_lag: int = lag_min
	var best_score := -1.0
	for lag in range(lag_min, lag_max + 1):
		var s := 0.0
		for i in range(lag, n):
			s += flux[i] * flux[i - lag]
		if s > best_score:
			best_score = s
			best_lag = lag
	if best_score <= 0.0:
		return res
	var beat_period: float = float(best_lag) * dt
	if beat_period <= 0.0:
		return res
	var bpm: float = 60.0 / beat_period
	# ③ 相位：1 小节内找能量最强的起点
	var bar: float = beat_period * 4.0
	var best_off := 0.0
	var best_off_score := -1.0
	var psteps: int = 32
	for s in psteps:
		var off: float = (float(s) / float(psteps)) * bar
		var sc := 0.0
		var k := 0
		while off + float(k) * bar < dur:
			var idx: int = int((off + float(k) * bar) / dt)
			if idx >= 0 and idx < n:
				sc += flux[idx]
			k += 1
		if sc > best_off_score:
			best_off_score = sc
			best_off = off
	var anchor: float = best_off
	var marks = []
	var mk: float = anchor
	while mk < dur:
		marks.append(mk)
		mk += bar
	res.anchor = anchor
	res.marks = marks
	res.bpm = bpm
	return res

## float32 [-1,1] → 16-bit PCM 字节。
static func _float32_to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var out = PackedByteArray()
	out.resize(samples.size() * 2)
	for i in samples.size():
		var v = clampi(int(samples[i] * 32767.0), -32768, 32767)
		out[i * 2] = v & 0xFF
		out[i * 2 + 1] = (v >> 8) & 0xFF
	return out

static func _u32(v: int) -> PackedByteArray:
	var b = PackedByteArray()
	b.resize(4)
	b[0] = v & 0xFF
	b[1] = (v >> 8) & 0xFF
	b[2] = (v >> 16) & 0xFF
	b[3] = (v >> 24) & 0xFF
	return b

static func _u16(v: int) -> PackedByteArray:
	var b = PackedByteArray()
	b.resize(2)
	b[0] = v & 0xFF
	b[1] = (v >> 8) & 0xFF
	return b

## 把 float32 样本写成标准 16-bit 单声道 WAV。自动创建父目录。
static func write_wav(path: String, samples: PackedFloat32Array, sr: int = 44100) -> bool:
	if samples.size() == 0:
		return false
	var data = _float32_to_pcm16(samples)
	var dir = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var header = PackedByteArray()
	header.append_array("RIFF".to_ascii_buffer())
	header.append_array(_u32(36 + data.size()))
	header.append_array("WAVE".to_ascii_buffer())
	header.append_array("fmt ".to_ascii_buffer())
	header.append_array(_u32(16))
	header.append_array(_u16(1))        # PCM
	header.append_array(_u16(1))        # mono
	header.append_array(_u32(sr))
	header.append_array(_u32(sr * 2))   # byte rate
	header.append_array(_u16(2))        # block align
	header.append_array(_u16(16))       # bits per sample
	header.append_array("data".to_ascii_buffer())
	header.append_array(_u32(data.size()))
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(header)
	f.store_buffer(data)
	f.close()
	return true

## Extract the first percussive hit from a recorded sample.
func _trim_hit(samples: PackedFloat32Array) -> PackedFloat32Array:
	if samples.size() == 0:
		return samples
	var threshold = 0.04
	var onset = -1
	for i in samples.size():
		if absf(samples[i]) > threshold:
			onset = i
			break
	if onset < 0:
		return samples.slice(0, mini(samples.size(), int(0.4 * MIX_RATE)))
	var start = maxi(0, onset - int(0.03 * MIX_RATE))
	var end = mini(samples.size(), onset + int(0.35 * MIX_RATE))
	return samples.slice(start, end)

## 取某音轨的真实录音样本。内存没有但磁盘有（user://samples/*.wav）时自动读盘并缓存，
## 这样即使内存样本被清掉（导航/重载时序等），也永远播真实录音、绝不变默认鼓。
func _recorded_sample_for_track(track: int) -> PackedFloat32Array:
	if _recorded_samples.has(track) and _recorded_samples[track].size() > 0:
		return _recorded_samples[track]
	var all = GameState.all_instruments()
	if track >= 0 and track < all.size():
		var inst: Dictionary = all[track]
		if inst.get("custom", false):
			var s = _read_wav_samples(inst.get("wav", ""))
			if s.size() > 0:
				_recorded_samples[track] = s
				return s
	return PackedFloat32Array()

func _queue_voice(track: int, pitch: int, vel: float, delay_frames: int) -> void:
	var s: PackedFloat32Array = _recorded_sample_for_track(track)
	if s.size() == 0:
		match track:
			0: s = Synth.kick(MIX_RATE, pitch, vel)
			1: s = Synth.woodblock(MIX_RATE, pitch, vel)
			2: s = Synth.bell(MIX_RATE, pitch, vel)
			_: s = Synth.tom(MIX_RATE, pitch, vel)   # 仅当真实样本确实缺失时退化（纸箱）
	if s.size() == 0:
		return   # 绝不让空样本进入混音器
	_voices.append({"samples": s, "pos": -delay_frames})

func _fire_step(step: int) -> void:
	for t in TRACKS:
		var cell = _patterns[t][step]
		if cell != null:
			_queue_voice(t, cell.get("pitch", 0), cell.get("vel", 1.0), 0)
	step_changed.emit(step)

func _process(_delta: float) -> void:
	if _playback == null:
		return
	var avail = _playback.get_frames_available()
	if avail <= 0:
		return
	var sps = samples_per_step()
	for i in avail:
		if playing and _sample_counter >= _next_step_pos:
			_fire_step(current_step)
			current_step = (current_step + 1) % steps
			_next_step_pos += sps
		var v = 0.0
		for voice in _voices:
			var p: int = voice.pos
			if p >= 0 and p < voice.samples.size():
				v += voice.samples[p]
			voice.pos = p + 1
		v = clampf(v, -1.0, 1.0) * 0.9 * rhythm_volume
		_playback.push_frame(Vector2(v, v))
		if recording:
			_rec_buffer.append(v)
		_sample_counter += 1
	# cull finished voices
	if _voices.size() > 0:
		_voices = _voices.filter(func(vc): return vc.pos < vc.samples.size())
