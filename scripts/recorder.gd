class_name Recorder
extends RefCounted
## Microphone recording helper for TrashBeats.
## Godot 4 mic chain: AudioStreamMicrophone player → "Microphone" bus with
## AudioEffectCapture (bus muted so there's no speaker feedback).
## Requires audio/driver/enable_input=true (set in project.godot).
## Gracefully degrades when no microphone is available.

const SAMPLE_RATE = 44100

## Whether microphone capture is usable in the current environment.
## Godot's HTML5/WebGL export has no AudioEffectCapture / AudioStreamMicrophone
## support, so the "tap-to-record" flow must fall back to procedural synth there.
static func is_capture_supported() -> bool:
	return not (OS.has_feature("web") or OS.get_name() == "Web")

var _capture_effect: AudioEffectCapture = null
var _mic_player: AudioStreamPlayer = null
var _host: Node = null
var _recording = false
var _buffer: PackedFloat32Array
var _bus_index = -1
var _available = false

func setup(host: Node = null) -> bool:
	_host = host

	var bus_name = "Microphone"
	_bus_index = AudioServer.get_bus_index(bus_name)
	if _bus_index < 0:
		_bus_index = AudioServer.bus_count
		AudioServer.add_bus(_bus_index)
		AudioServer.set_bus_name(_bus_index, bus_name)

	# Capture effect on the mic bus
	_capture_effect = AudioEffectCapture.new()
	AudioServer.add_bus_effect(_bus_index, _capture_effect, 0)

	# Mute output — we only want captured samples, no speaker feedback
	AudioServer.set_bus_mute(_bus_index, true)

	# Route the physical mic into the bus (Godot 4 way: AudioStreamMicrophone)
	if host != null:
		_mic_player = AudioStreamPlayer.new()
		_mic_player.stream = AudioStreamMicrophone.new()
		_mic_player.bus = bus_name
		host.add_child(_mic_player)
		_mic_player.play()

	_available = true
	return true

func teardown() -> void:
	_recording = false
	if _mic_player:
		_mic_player.stop()
		_mic_player.queue_free()
		_mic_player = null
	if _bus_index >= 0 and _capture_effect:
		# remove exactly our effect instance (bus is shared)
		for i in AudioServer.get_bus_effect_count(_bus_index):
			if AudioServer.get_bus_effect(_bus_index, i) == _capture_effect:
				AudioServer.remove_bus_effect(_bus_index, i)
				break
		_capture_effect = null
	_available = false

func available() -> bool:
	return _available

func start_recording() -> void:
	if not _available or _capture_effect == null:
		return
	_buffer = PackedFloat32Array()
	_capture_effect.clear_buffer()
	_recording = true

func stop_recording() -> PackedFloat32Array:
	_recording = false
	if _buffer.size() == 0:
		return PackedFloat32Array()
	return _trim(_buffer)

func is_recording() -> bool:
	return _recording

func process() -> void:
	if not _recording or _capture_effect == null:
		return
	var frames = _capture_effect.get_frames_available()
	if frames > 0:
		# get_buffer returns PackedVector2Array (stereo L/R)
		var stereo: PackedVector2Array = _capture_effect.get_buffer(frames)
		# Extract left channel only → PackedFloat32Array
		var mono = PackedFloat32Array()
		mono.resize(stereo.size())
		for i in stereo.size():
			mono[i] = stereo[i].x
		_buffer.append_array(mono)

func save_wav(path: String, samples: PackedFloat32Array) -> void:
	if samples.size() == 0:
		return
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	# Convert PackedFloat32Array [-1,1] → PackedByteArray (16-bit PCM)
	wav.data = _float32_to_pcm16(samples)
	wav.save_to_wav(path)

func _float32_to_pcm16(samples: PackedFloat32Array) -> PackedByteArray:
	var out = PackedByteArray()
	out.resize(samples.size() * 2)
	for i in samples.size():
		var v = clampi(int(samples[i] * 32767.0), -32768, 32767)
		out[i * 2] = v & 0xFF
		out[i * 2 + 1] = (v >> 8) & 0xFF
	return out

## Trim leading/trailing silence and extract the first meaningful hit
func _trim(samples: PackedFloat32Array) -> PackedFloat32Array:
	if samples.size() == 0:
		return samples
	var threshold = 0.04
	var onset = -1
	var offset = -1
	for i in samples.size():
		if onset < 0 and absf(samples[i]) > threshold:
			onset = i
		if onset >= 0 and absf(samples[i]) > threshold:
			offset = i
	if onset < 0:
		return samples.slice(0, mini(samples.size(), int(0.5 * SAMPLE_RATE)))
	var start = maxi(0, onset - int(0.05 * SAMPLE_RATE))
	var end = mini(samples.size(), offset + int(0.15 * SAMPLE_RATE))
	return samples.slice(start, end)
