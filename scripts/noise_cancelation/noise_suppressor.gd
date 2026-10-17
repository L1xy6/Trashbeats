class_name NoiseSuppressor
extends RefCounted

## Streaming voice-focused noise suppressor for normalized PCM samples.
## The implementation is dependency-free and compatible with native and Web builds.

const FRAME_SIZE := 512
const HOP_SIZE := 256
const BIN_COUNT := 257
const EPSILON := 1.0e-12

var suppression_strength := 1.15
var isolation_strength := 0.35
var minimum_gain_db := -24.0
var calibration_ms := 500.0
var high_pass_hz := 75.0

var _sample_rate := 48000.0
var _window := PackedFloat32Array()
var _input_buffer := PackedFloat32Array()
var _overlap := PackedFloat32Array()
var _noise_power := PackedFloat32Array()
var _smoothed_gain := PackedFloat32Array()
var _calibration_frames := 1
var _frames_seen := 0
var _learning_enabled := true
var _previous_input := 0.0
var _previous_high_pass := 0.0


func _init(sample_rate := 48000.0) -> void:
	configure(sample_rate)


func configure(sample_rate: float, profile_ms := 500.0) -> void:
	_sample_rate = maxf(sample_rate, 8000.0)
	calibration_ms = maxf(profile_ms, 0.0)
	_calibration_frames = maxi(
		1,
		int(ceil(calibration_ms * _sample_rate / (1000.0 * HOP_SIZE)))
	)
	_build_window()
	reset()


func reset() -> void:
	_input_buffer = PackedFloat32Array()
	_overlap = _filled_array(FRAME_SIZE, 0.0)
	_noise_power = _filled_array(BIN_COUNT, EPSILON)
	_smoothed_gain = _filled_array(BIN_COUNT, 1.0)
	_frames_seen = 0
	_learning_enabled = true
	_previous_input = 0.0
	_previous_high_pass = 0.0


func set_noise_learning(enabled: bool) -> void:
	_learning_enabled = enabled


func is_calibrating() -> bool:
	return _frames_seen < _calibration_frames


func latency_samples() -> int:
	return FRAME_SIZE


func process_mono(samples: PackedFloat32Array) -> PackedFloat32Array:
	if samples.is_empty():
		return PackedFloat32Array()

	var filtered := PackedFloat32Array()
	filtered.resize(samples.size())
	for index in samples.size():
		filtered[index] = _high_pass(clampf(samples[index], -1.0, 1.0))
	_input_buffer.append_array(filtered)

	var output := PackedFloat32Array()
	while _input_buffer.size() >= FRAME_SIZE:
		var frame := _input_buffer.slice(0, FRAME_SIZE)
		var processed := _process_frame(frame)
		for index in FRAME_SIZE:
			_overlap[index] += processed[index]
		output.append_array(_overlap.slice(0, HOP_SIZE))
		_shift_overlap()
		_input_buffer = _input_buffer.slice(HOP_SIZE)

	return output


func process_interleaved(
	samples: PackedFloat32Array,
	channel_count: int
) -> PackedFloat32Array:
	if channel_count <= 1:
		return process_mono(samples)
	if samples.is_empty():
		return PackedFloat32Array()

	var frame_count := int(samples.size() / channel_count)
	var mono := PackedFloat32Array()
	mono.resize(frame_count)
	for frame_index in frame_count:
		var mixed := 0.0
		for channel_index in channel_count:
			mixed += samples[frame_index * channel_count + channel_index]
		mono[frame_index] = mixed / channel_count

	var processed_mono := process_mono(mono)
	var output := PackedFloat32Array()
	output.resize(processed_mono.size() * channel_count)
	for frame_index in processed_mono.size():
		for channel_index in channel_count:
			output[frame_index * channel_count + channel_index] = processed_mono[frame_index]
	return output


func flush() -> PackedFloat32Array:
	if _input_buffer.is_empty():
		return PackedFloat32Array()
	var padding := PackedFloat32Array()
	padding.resize(FRAME_SIZE)
	var output := process_mono(padding)
	_input_buffer = PackedFloat32Array()
	return output


func _process_frame(frame: PackedFloat32Array) -> PackedFloat32Array:
	var real := PackedFloat32Array()
	var imaginary := PackedFloat32Array()
	real.resize(FRAME_SIZE)
	imaginary.resize(FRAME_SIZE)
	for index in FRAME_SIZE:
		real[index] = frame[index] * _window[index]

	_fft(real, imaginary, false)

	var power := PackedFloat32Array()
	power.resize(BIN_COUNT)
	for bin_index in BIN_COUNT:
		power[bin_index] = (
			real[bin_index] * real[bin_index]
			+ imaginary[bin_index] * imaginary[bin_index]
			+ EPSILON
		)

	var speech_probability := _estimate_speech_probability(power)
	_update_noise_profile(power, speech_probability)
	var gains := _calculate_gains(power, speech_probability)
	_apply_gains(real, imaginary, gains)
	_fft(real, imaginary, true)

	var output := PackedFloat32Array()
	output.resize(FRAME_SIZE)
	for index in FRAME_SIZE:
		output[index] = real[index] * _window[index]
	_frames_seen += 1
	return output


func _estimate_speech_probability(power: PackedFloat32Array) -> float:
	if is_calibrating():
		return 0.0

	var bin_hz := _sample_rate / FRAME_SIZE
	var first_bin := clampi(int(100.0 / bin_hz), 1, BIN_COUNT - 1)
	var last_bin := clampi(int(7000.0 / bin_hz), first_bin + 1, BIN_COUNT)
	var log_ratio_sum := 0.0
	var count := 0
	for bin_index in range(first_bin, last_bin):
		var ratio := power[bin_index] / maxf(_noise_power[bin_index], EPSILON)
		log_ratio_sum += log(maxf(ratio, EPSILON))
		count += 1

	var mean_snr_db := 10.0 * (log_ratio_sum / maxf(count, 1)) / log(10.0)
	return _smoothstep(1.5, 7.0, mean_snr_db)


func _update_noise_profile(
	power: PackedFloat32Array,
	speech_probability: float
) -> void:
	if not _learning_enabled:
		return

	if is_calibrating():
		var blend := 1.0 / float(_frames_seen + 1)
		for bin_index in BIN_COUNT:
			_noise_power[bin_index] = lerpf(
				_noise_power[bin_index],
				power[bin_index],
				blend
			)
		return

	for bin_index in BIN_COUNT:
		var ratio := power[bin_index] / maxf(_noise_power[bin_index], EPSILON)
		var update_rate := lerpf(0.055, 0.002, speech_probability)
		if ratio < 1.0:
			update_rate = 0.12
		_noise_power[bin_index] = lerpf(
			_noise_power[bin_index],
			power[bin_index],
			update_rate
		)


func _calculate_gains(
	power: PackedFloat32Array,
	speech_probability: float
) -> PackedFloat32Array:
	var target := PackedFloat32Array()
	target.resize(BIN_COUNT)
	var minimum_gain := db_to_linear(minimum_gain_db)
	var gate_gain := lerpf(1.0 - isolation_strength, 1.0, speech_probability)

	for bin_index in BIN_COUNT:
		var posterior_snr := power[bin_index] / maxf(_noise_power[bin_index], EPSILON)
		var prior_snr := maxf(posterior_snr - 1.0, 0.0)
		var wiener_gain := prior_snr / (prior_snr + 1.0)
		var subtraction_gain := sqrt(maxf(
			1.0 - suppression_strength / maxf(posterior_snr, EPSILON),
			0.0
		))
		var combined := sqrt(wiener_gain * subtraction_gain)
		target[bin_index] = clampf(combined * gate_gain, minimum_gain, 1.0)

	var frequency_smoothed := PackedFloat32Array()
	frequency_smoothed.resize(BIN_COUNT)
	for bin_index in BIN_COUNT:
		var left := target[maxi(bin_index - 1, 0)]
		var center := target[bin_index]
		var right := target[mini(bin_index + 1, BIN_COUNT - 1)]
		frequency_smoothed[bin_index] = left * 0.2 + center * 0.6 + right * 0.2

	for bin_index in BIN_COUNT:
		var rate := 0.45 if frequency_smoothed[bin_index] < _smoothed_gain[bin_index] else 0.08
		_smoothed_gain[bin_index] = lerpf(
			_smoothed_gain[bin_index],
			frequency_smoothed[bin_index],
			rate
		)
	return _smoothed_gain.duplicate()


func _apply_gains(
	real: PackedFloat32Array,
	imaginary: PackedFloat32Array,
	gains: PackedFloat32Array
) -> void:
	for bin_index in BIN_COUNT:
		var gain := gains[bin_index]
		real[bin_index] *= gain
		imaginary[bin_index] *= gain
		if bin_index > 0 and bin_index < HOP_SIZE:
			var mirror := FRAME_SIZE - bin_index
			real[mirror] *= gain
			imaginary[mirror] *= gain


func _high_pass(sample: float) -> float:
	if high_pass_hz <= 0.0:
		return sample
	var delta := 1.0 / _sample_rate
	var time_constant := 1.0 / (TAU * high_pass_hz)
	var alpha := time_constant / (time_constant + delta)
	var output := alpha * (_previous_high_pass + sample - _previous_input)
	_previous_input = sample
	_previous_high_pass = output
	return output


func _shift_overlap() -> void:
	for index in HOP_SIZE:
		_overlap[index] = _overlap[index + HOP_SIZE]
		_overlap[index + HOP_SIZE] = 0.0


func _build_window() -> void:
	_window.resize(FRAME_SIZE)
	for index in FRAME_SIZE:
		var hann := 0.5 - 0.5 * cos(TAU * index / FRAME_SIZE)
		_window[index] = sqrt(maxf(hann, 0.0))


func _fft(
	real: PackedFloat32Array,
	imaginary: PackedFloat32Array,
	inverse: bool
) -> void:
	var size := real.size()
	var swap_index := 0
	for index in range(1, size):
		var bit := size >> 1
		while (swap_index & bit) != 0:
			swap_index ^= bit
			bit >>= 1
		swap_index ^= bit
		if index < swap_index:
			var real_value := real[index]
			real[index] = real[swap_index]
			real[swap_index] = real_value
			var imaginary_value := imaginary[index]
			imaginary[index] = imaginary[swap_index]
			imaginary[swap_index] = imaginary_value

	var length := 2
	while length <= size:
		var angle := TAU / length * (1.0 if inverse else -1.0)
		var step_real := cos(angle)
		var step_imaginary := sin(angle)
		for offset in range(0, size, length):
			var twiddle_real := 1.0
			var twiddle_imaginary := 0.0
			var half_length := int(length / 2)
			for pair_index in range(half_length):
				var even_index := offset + pair_index
				var odd_index := even_index + half_length
				var odd_real := (
					real[odd_index] * twiddle_real
					- imaginary[odd_index] * twiddle_imaginary
				)
				var odd_imaginary := (
					real[odd_index] * twiddle_imaginary
					+ imaginary[odd_index] * twiddle_real
				)
				real[odd_index] = real[even_index] - odd_real
				imaginary[odd_index] = imaginary[even_index] - odd_imaginary
				real[even_index] += odd_real
				imaginary[even_index] += odd_imaginary
				var next_twiddle_real := (
					twiddle_real * step_real
					- twiddle_imaginary * step_imaginary
				)
				twiddle_imaginary = (
					twiddle_real * step_imaginary
					+ twiddle_imaginary * step_real
				)
				twiddle_real = next_twiddle_real
		length <<= 1

	if inverse:
		for index in size:
			real[index] /= size
			imaginary[index] /= size


func _smoothstep(edge_start: float, edge_end: float, value: float) -> float:
	var amount := clampf((value - edge_start) / (edge_end - edge_start), 0.0, 1.0)
	return amount * amount * (3.0 - 2.0 * amount)


func _filled_array(size: int, value: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	result.resize(size)
	result.fill(value)
	return result
