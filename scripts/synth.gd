class_name Synth
extends RefCounted
## Procedural "trash instrument" voices, synthesized into mono PCM buffers.
## Stands in for the proposal's 后端音频处理 (录音 + AI 降噪调音): in the full
## product these would be recorded hits cleaned up server-side; here we
## synthesize approximations so the prototype is fully offline.

static func _pitch_mult(semis: int) -> float:
	return pow(2.0, semis / 12.0)

## 铝制易拉罐 · 808 — deep kick with pitch drop + click transient
static func kick(rate: int, semis: int = 0, gain: float = 1.0) -> PackedFloat32Array:
	var n = int(0.45 * rate)
	var out = PackedFloat32Array()
	out.resize(n)
	var mult = _pitch_mult(semis)
	var phase = 0.0
	var click_len = int(0.004 * rate)
	for i in n:
		var t = float(i) / rate
		var f = (45.0 + 105.0 * exp(-t * 28.0)) * mult
		phase += TAU * f / rate
		var s = sin(phase) * exp(-t * 9.0)
		if i < click_len:
			s += (randf() * 2.0 - 1.0) * 0.35 * (1.0 - float(i) / click_len)
		out[i] = s * gain
	return out

## 塑料瓶 · 电子木鱼 — short hollow knock
static func woodblock(rate: int, semis: int = 0, gain: float = 1.0) -> PackedFloat32Array:
	var n = int(0.09 * rate)
	var out = PackedFloat32Array()
	out.resize(n)
	var mult = _pitch_mult(semis)
	for i in n:
		var t = float(i) / rate
		var s = sin(TAU * 780.0 * mult * t) * exp(-t * 70.0)
		s += 0.5 * sin(TAU * 1150.0 * mult * t) * exp(-t * 95.0)
		s += (randf() * 2.0 - 1.0) * 0.35 * exp(-t * 140.0)
		out[i] = s * gain * 0.9
	return out

## 玻璃瓶 · 清铃 — inharmonic bell with long decay
static func bell(rate: int, semis: int = 0, gain: float = 1.0) -> PackedFloat32Array:
	var n = int(0.9 * rate)
	var out = PackedFloat32Array()
	out.resize(n)
	var mult = _pitch_mult(semis)
	var f = 620.0 * mult
	var attack = int(0.003 * rate)
	for i in n:
		var t = float(i) / rate
		var s = sin(TAU * f * t)
		s += 0.5 * sin(TAU * f * 2.76 * t)
		s += 0.22 * sin(TAU * f * 5.40 * t)
		var env = exp(-t * 4.5)
		if i < attack:
			env *= float(i) / attack
		out[i] = s * env * gain * 0.55
	return out


## 纸箱 · 闷鼓 — muffled low tom: thump + lowpassed noise
static func tom(rate: int, semis: int = 0, gain: float = 1.0) -> PackedFloat32Array:
	var n = int(0.28 * rate)
	var out = PackedFloat32Array()
	out.resize(n)
	var mult = _pitch_mult(semis)
	var phase = 0.0
	var lp = 0.0
	for i in n:
		var t = float(i) / rate
		var f = (70.0 + 40.0 * exp(-t * 30.0)) * mult
		phase += TAU * f / rate
		var thump = sin(phase) * exp(-t * 14.0)
		lp += 0.12 * ((randf() * 2.0 - 1.0) - lp)
		var s = thump + lp * 1.6 * exp(-t * 20.0)
		out[i] = s * gain * 0.85
	return out

