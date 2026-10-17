class_name MelodyGenerator
extends Node
## 封装 QQ 音乐天琴工作流 (DoTianQinWorkFlow) API。
## 异步两步：提交任务 → 轮询结果 → 下载 MP3。
## 签名用 HMAC-SHA256（Godot 无内置 HMAC，用 HashingContext 手动实现）。

signal task_submitted(task_id: String)
signal poll_status_changed(status: int, url: String)  # 0=生成中 1=成功 2=失败
signal download_complete(path: String)
signal error(msg: String)

const APP_ID_ENV = "TRASHBEATS_TIANQIN_APP_ID"
const APP_KEY_ENV = "TRASHBEATS_TIANQIN_APP_KEY"
const CONFIGURATION_ERROR = "在线旋律尚未配置。请设置环境变量 TRASHBEATS_TIANQIN_APP_ID 和 TRASHBEATS_TIANQIN_APP_KEY 后重新启动；也可继续使用本地编曲和 WAV 导入。"
const API_URL = "https://test.y.qq.com/opentest/rpc_proxy/fcgi-bin/music_open_api.fcg"

var _http: HTTPRequest
var _poll_timer: Timer
var _poll_count = 0
const MAX_POLLS = 60  # 最多轮询 60 次 × 5s = 5 分钟

var _current_task_id = ""
var _save_path = ""
var _busy = false   # HTTPRequest 同一时刻只能跑一个请求

static func is_configured() -> bool:
	return not OS.get_environment(APP_ID_ENV).strip_edges().is_empty() \
		and not OS.get_environment(APP_KEY_ENV).strip_edges().is_empty()

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 60.0
	add_child(_http)
	_poll_timer = Timer.new()
	_poll_timer.wait_time = 5.0
	_poll_timer.one_shot = false
	_poll_timer.timeout.connect(_on_poll_tick)
	add_child(_poll_timer)

# ── HMAC-SHA256（手动实现，Godot 无内置 HMAC）──────────────

static func _hmac_sha256(key: PackedByteArray, message: String) -> String:
	var msg = message.to_utf8_buffer()
	var bs = 64
	var k = key.duplicate()
	if k.size() > bs:
		var h = HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		h.update(k)
		k = h.finish()
	k.resize(bs)  # 短 key 补零
	var ipad = PackedByteArray()
	ipad.resize(bs)
	var opad = PackedByteArray()
	opad.resize(bs)
	for i in bs:
		ipad[i] = k[i] ^ 0x36
		opad[i] = k[i] ^ 0x5C
	# inner = H(ipad || msg)
	var ic = HashingContext.new()
	ic.start(HashingContext.HASH_SHA256)
	ic.update(ipad)
	ic.update(msg)
	var inner = ic.finish()
	# outer = H(opad || inner)
	var oc = HashingContext.new()
	oc.start(HashingContext.HASH_SHA256)
	oc.update(opad)
	oc.update(inner)
	return oc.finish().hex_encode()

# ── 紧凑 JSON 序列化（无空格，匹配 Python separators=(',',':')）──

static func _compact_json(obj) -> String:
	return JSON.stringify(obj, "")

# ── 核心请求（双重序列化 + 签名 + POST）────────────────────

func _send_post(cmd: String, biz_data: Dictionary) -> Dictionary:
	if not is_configured():
		error.emit(CONFIGURATION_ERROR)
		return {}
	var timestamp = str(int(Time.get_unix_time_from_system()))
	var unique_id = "probe-%s" % timestamp
	# 第一层：biz_data 紧凑序列化
	var biz_str = _compact_json(biz_data)
	# 第二层：完整 payload 紧凑序列化
	var payload = {
		"comm": {
			"app_id": OS.get_environment(APP_ID_ENV).strip_edges(),
			"timestamp": timestamp,
			"opi_cmd": "DoTianQinWorkFlow"
		},
		"cgi": {
			"cmd": cmd,
			"unique_id": unique_id,
			"data": biz_str
		}
	}
	var raw_body = _compact_json(payload)
	# 签名
	var plain_text = raw_body + "&cookie="
	var sign = _hmac_sha256(OS.get_environment(APP_KEY_ENV).strip_edges().to_utf8_buffer(), plain_text)
	var headers = PackedStringArray([
		"Content-Type: application/json",
		"X-QYOPI-Sign: %s" % sign
	])
	# 同步请求（用 await）；HTTPRequest 同时只能有一个在飞
	if _busy:
		return {}
	_busy = true
	var err = _http.request(API_URL, headers, HTTPClient.METHOD_POST, raw_body)
	if err != OK:
		_busy = false
		error.emit("请求发起失败 err=%d" % err)
		return {}
	var resp = await _http.request_completed
	_busy = false
	# resp = [result, code, headers, body]
	var body = resp[3] as PackedByteArray
	var text = body.get_string_from_utf8()
	var json = JSON.new()
	if json.parse(text) != OK:
		error.emit("响应解析失败: %s" % text.left(200))
		return {}
	var res = json.data as Dictionary
	if res.get("ret") != 0:
		error.emit("接口错误 ret=%s msg=%s" % [res.get("ret"), res.get("msg", "")])
		return {}
	# 二次解析内层 data 字符串
	var inner_str = res.get("data", "")
	var inner_json = JSON.new()
	if inner_str is String:
		if inner_json.parse(inner_str) != OK:
			error.emit("内层 data 解析失败")
			return {}
		return inner_json.data as Dictionary
	return inner_str as Dictionary

# ── Step 1: 提交生成任务 ──────────────────────────────────

func submit_task(lyrics: String, tags: String) -> void:
	_current_task_id = ""  # A failed submission must not resume an earlier task.
	var biz = {
		"inputs": {
			"lyrics": lyrics,
			"tags": tags,
			"generate_mode": 1,
			"song_num": 1
		}
	}
	var inner = await _send_post("api/v1/workflow/async/run", biz)
	if inner.is_empty():
		return
	if inner.get("code") != 0:
		error.emit("业务错误: %s" % inner.get("msg", ""))
		return
	_current_task_id = inner.get("taskId", "")
	if _current_task_id == "":
		error.emit("未获取到 taskId")
		return
	task_submitted.emit(_current_task_id)

# ── Step 2: 轮询任务状态 ──────────────────────────────────

func start_polling(task_id: String, save_path: String) -> void:
	if not is_configured():
		error.emit(CONFIGURATION_ERROR)
		return
	_current_task_id = task_id
	_save_path = save_path
	_poll_count = 0
	_poll_timer.start()

func _on_poll_tick() -> void:
	if _current_task_id == "":
		_poll_timer.stop()
		return
	_poll_count += 1
	if _poll_count > MAX_POLLS:
		_poll_timer.stop()
		error.emit("生成超时（5 分钟）")
		return
	var biz = {"taskId": _current_task_id}
	var inner = await _send_post("api/v1/workflow/result/poll", biz)
	if inner.is_empty():
		_poll_timer.stop()
		return
	var ps = inner.get("poll_status", -1)
	if ps == 0:
		# 仍在生成，继续等
		return
	elif ps == 1:
		_poll_timer.stop()
		var result_data = inner.get("data")
		if result_data is String:
			var j = JSON.new()
			if j.parse(result_data) == OK:
				result_data = j.data
		if result_data is Dictionary:
			var iter_output = result_data.get("iter_output", [])
			if iter_output.size() > 0:
				var audio_url = iter_output[0].get("full_decode_url", "")
				if audio_url != "":
					poll_status_changed.emit(1, audio_url)
					_download_mp3(audio_url, _save_path)
					return
		error.emit("成功但未找到下载链接")
	elif ps == 2:
		_poll_timer.stop()
		poll_status_changed.emit(2, "")
		error.emit("任务失败或超时")
	else:
		_poll_timer.stop()
		error.emit("未知状态: %d" % ps)

# ── Step 3: 下载 MP3 ─────────────────────────────────────

func _download_mp3(url: String, save_path: String) -> void:
	if _busy:
		error.emit("下载失败：网络繁忙")
		return
	_busy = true
	var err = _http.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "")
	if err != OK:
		_busy = false
		error.emit("下载发起失败 err=%d" % err)
		return
	var resp = await _http.request_completed
	_busy = false
	var body = resp[3] as PackedByteArray
	if body.size() == 0:
		error.emit("下载失败：空响应")
		return
	var dir = save_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f = FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		error.emit("无法写入: %s" % save_path)
		return
	f.store_buffer(body)
	f.close()
	download_complete.emit(save_path)

# ── 一站式调用（提交 + 轮询 + 下载）────────────────────────

func generate(lyrics: String, tags: String, save_path: String) -> void:
	await submit_task(lyrics, tags)
	if _current_task_id != "":
		start_polling(_current_task_id, save_path)

func cancel() -> void:
	_poll_timer.stop()
	_current_task_id = ""
