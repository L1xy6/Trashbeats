class_name SoundEdit
extends RefCounted
## SoundEdit — turn a user microphone recording into a clean, standardized
## one-shot hit (~0.3s) that sits well in the step sequencer.
##
## Pipeline (all plain GDScript, no external DSP libs, so it always runs):
##   1. resample to the target rate if the source differs
##   2. NoiseSuppressor streaming denoise (spectral subtraction + Wiener filter)
##   3. one-pole high-pass (~70 Hz) to kill handling rumble / low noise
##   4. locate the global peak and slice a fixed target_dur window around it
##   5. noise gate to kill the hiss before/after the hit
##   6. one-pole low-pass (~9 kHz) to kill high-frequency hiss
##   7. normalize peak + tanh soft-clip (compress dynamics into a consistent hit)

const DEFAULT_SR := 44100
const NOISE_SUPPRESSOR := preload("res://scripts/noise_cancelation/noise_suppressor.gd")

## samples : mono float32 buffer in [-1, 1]
## sr      : sample rate of `samples`
## target_dur : final hit length in seconds (default 0.3)
## target_sr  : output sample rate (default 44100, matches the audio engine)
static func process_hit(samples: PackedFloat32Array, sr: int = DEFAULT_SR, target_dur: float = 0.3, target_sr: int = DEFAULT_SR) -> PackedFloat32Array:
	if samples == null or samples.size() == 0:
		return PackedFloat32Array()

	var x := samples.duplicate()

	# 1) sample-rate match
	if sr != target_sr:
		x = _resample(x, sr, target_sr)

	# 2) NoiseSuppressor: streaming spectral denoise (Wiener + subtraction)
	x = _denoise(x, target_sr)

	# 3) high-pass to remove low-frequency rumble / handling noise
	x = _highpass(x, target_sr, 70.0)

	# 4) find the global peak and slice a fixed window just after it
	var peak_idx := _global_peak(x)
	var attack := int(0.02 * target_sr)          # 20 ms of attack before the peak
	var start := maxi(0, peak_idx - attack)
	var out_len := int(target_dur * target_sr)
	var seg := x.slice(start, mini(x.size(), start + out_len))

	# pad the tail with silence so the result is exactly target_dur long
	if seg.size() < out_len:
		var padded := PackedFloat32Array()
		padded.resize(out_len)
		for i in seg.size():
			padded[i] = seg[i]
		seg = padded

	# 5) noise gate (kill hiss below the floor)
	seg = _noise_gate(seg, 0.015)

	# 6) low-pass to soften high-frequency hiss
	seg = _lowpass(seg, target_sr, 9000.0)

	# 7) normalize peak + soft-clip (compress dynamics for a consistent hit)
	seg = _normalize(seg, 0.9)
	seg = _softclip(seg, 1.4)

	return seg

# ── internal DSP helpers ──────────────────────────────────────────────

static func _resample(x: PackedFloat32Array, sr: int, target_sr: int) -> PackedFloat32Array:
	var n := int(float(x.size()) * float(target_sr) / float(sr))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var src := float(i) * float(sr) / float(target_sr)
		var i0 := int(src)
		var i1 := mini(i0 + 1, x.size() - 1)
		var f := src - float(i0)
		out[i] = lerpf(x[i0], x[i1], f)
	return out

static func _highpass(x: PackedFloat32Array, sr: int, fc: float) -> PackedFloat32Array:
	var out := x.duplicate()
	var rc := 1.0 / (2.0 * PI * fc)
	var dt := 1.0 / float(sr)
	var a := rc / (rc + dt)
	var prev_in := 0.0
	var prev_out := 0.0
	for i in out.size():
		var cur := out[i]
		var o := a * (prev_out + cur - prev_in)
		prev_in = cur
		prev_out = o
		out[i] = o
	return out

static func _lowpass(x: PackedFloat32Array, sr: int, fc: float) -> PackedFloat32Array:
	var out := x.duplicate()
	var rc := 1.0 / (2.0 * PI * fc)
	var dt := 1.0 / float(sr)
	var a := dt / (rc + dt)
	var prev := 0.0
	for i in out.size():
		prev = prev + a * (out[i] - prev)
		out[i] = prev
	return out

static func _global_peak(x: PackedFloat32Array) -> int:
	var best := 0
	var best_v := 0.0
	for i in x.size():
		var v := absf(x[i])
		if v > best_v:
			best_v = v
			best = i
	return best

static func _noise_gate(x: PackedFloat32Array, floor_amp: float) -> PackedFloat32Array:
	for i in x.size():
		if absf(x[i]) < floor_amp:
			x[i] = 0.0
	return x

static func _normalize(x: PackedFloat32Array, target: float) -> PackedFloat32Array:
	var peak := 0.0
	for i in x.size():
		peak = maxf(peak, absf(x[i]))
	if peak <= 0.0:
		return x
	var g := target / peak
	for i in x.size():
		x[i] = clampf(x[i] * g, -1.0, 1.0)
	return x

static func _softclip(x: PackedFloat32Array, k: float) -> PackedFloat32Array:
	var denom := tanh(k)
	for i in x.size():
		x[i] = tanh(x[i] * k) / denom
	return x

# ── NoiseSuppressor wrapper ───────────────────────────────────────────

## Run the streaming NoiseSuppressor over the full sample buffer.
## The suppressor needs ~500ms of noise profile to calibrate, so we feed
## the entire recording through and flush at the end. Returns the denoised
## buffer (same length as input).
static func _denoise(x: PackedFloat32Array, sr: int) -> PackedFloat32Array:
	if x.size() == 0:
		return x
	var suppressor := NOISE_SUPPRESSOR.new(float(sr))
	# Configure for voice-focused cleanup with moderate strength
	suppressor.suppression_strength = 1.15
	suppressor.isolation_strength = 0.35
	suppressor.minimum_gain_db = -24.0
	# Feed the full recording through the streaming suppressor
	var out := suppressor.process_mono(x)
	# Flush remaining buffered frames
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
