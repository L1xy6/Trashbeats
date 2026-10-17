# Noise Suppression Backend

`scripts/noise_suppressor.gd` is a self-contained streaming backend for recorded
voice. It accepts normalized PCM (`-1.0` to `1.0`) and returns denoised PCM
without native libraries, making it suitable for Windows and Web exports.

## Algorithm

The backend uses 512-sample frames with 50% overlap and a square-root Hann
window. It combines:

- a 75 Hz high-pass filter for rumble and DC removal;
- startup noise profiling plus asymmetric runtime adaptation;
- Wiener filtering and spectral subtraction;
- frequency and temporal gain smoothing to reduce musical noise;
- speech-probability gating for stronger background isolation between phrases.

The first 500 ms should contain mostly room noise. Call
`set_noise_learning(false)` after a known calibration period when the background
changes unpredictably or recorded material contains continuous music.

## Adapter Example

```gdscript
var suppressor := NoiseSuppressor.new(48000.0)

func handle_capture(pcm: PackedFloat32Array) -> void:
	var clean_pcm := suppressor.process_mono(pcm)
	if not clean_pcm.is_empty():
		recording_backend.push_pcm(clean_pcm)
```

For interleaved input, use `process_interleaved(pcm, channel_count)`. The result
is voice-focused mono duplicated across the requested channels. The algorithm
adds `latency_samples()` of buffering; adapters should not assume every input
call immediately returns the same number of samples.

Tune `suppression_strength` between `0.8` and `1.5`,
`isolation_strength` between `0.0` and `0.7`, and `minimum_gain_db` between
`-12.0` and `-36.0`. Stronger settings remove more background sound but can
introduce speech artifacts. Process audio off the render thread when possible.

This is single-ended noise suppression, not acoustic echo cancellation. Echo
removal requires the speaker playback signal as a separate reference input.
